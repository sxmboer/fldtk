/*
 * Ported from FL/Fl_Help_View.H + src/Fl_Help_View.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). A ~4600-line mini HTML-subset layout/rendering
 * engine -- the largest single port attempted in this project so far.
 * Staged across multiple milestones; see PORTING.md's row for current
 * scope.
 *
 * **Milestone 1**: HTML tokenizer, core layout (`format()` minus
 * TABLE/TR/TD/TH), `draw()` built together with text selection (they
 * share one code path FLTK -- see the module-level `Mode` enum's
 * doc comment), `find()`, `load()` (file:/local path, plus non-file:
 * schemes via the new `fl.filename.openUri()`), the right-click
 * copy menu.
 *
 * **Milestone 2**: `<TABLE>`/`<TR>`/`<TD>`/`<TH>` support --
 * `formatTable()` (the column-width pre-scan, ported from
 * `format_table()`) plus the TABLE/TR/TD/TH branches in `format()`'s
 * main layout pass and the TD/TH border/bgcolor rect in `draw()`. See
 * `formatTable()`'s own doc comment for the column-width algorithm and
 * `TextBlock.border`/`.bgcolor`'s doc comment (already present since
 * Milestone 1, unused until now) for the per-cell state it fills in.
 *
 * **Real `<img>` pixel rendering**: `getImage()` (ported from
 * `Impl::get_image()`), a fixed "broken
 * image" `Pixmap` fallback (`brokenImage()`, a verbatim transcription
 * of FLTK's own inline `broken_xpm[]`), and `initialLoad_`
 * (FLTK's own `get()`-vs-`find()` refcount-management flag, an
 * instance field here rather than a process-wide `static`) are wired
 * into all four real call sites: `format()`'s and `formatTable()`'s
 * `<IMG>` layout branches (image size now comes from the real loaded
 * image, not a fixed 16x24 stand-in), `draw()`'s `<IMG>` branch (real
 * pixels now, via `Image.draw()`), and `freeData()` (releases every
 * image the document's initial `format()` pass loaded, matching
 * FLTK's own document-teardown contract). Recognizes whatever
 * `fl.shared_image.SharedImage`'s own format-detection handles (XBM/
 * XPM/PNM built in, plus anything registered via its `addHandler()`).
 * `fl.help_dialog` is Milestone 3, see `PORTING.md`'s own row for that
 * module.
 *
 * **Deliberate structural deviation**: FLTK splits this widget
 * into `Fl_Help_View` (the public shell) plus a private nested `Impl`
 * class holding all real state/logic, `unique_ptr`-owned. FLTK's
 * own doc comment on `get_image()` says exactly why: "A better
 * solution would be... but this would break the ABI!" -- the split
 * exists purely for C++ ABI stability. This port has no such
 * constraint, so `HelpView` collapses both into one class.
 *
 * **Selection measurement, without an offscreen buffer**: FLTK
 * measures character positions under the mouse (`begin_selection()`/
 * `extend_selection()`) by re-entering the *same* text-emission code
 * `draw()` uses, routed through a `draw_mode_` flag (`Mode.push`/
 * `Mode.drag` suppress the actual `hv_draw()` text output but still
 * walk the layout and update the module-level `selectionPush*_`/
 * `selectionDrag*_` offsets) -- wrapped in `beginOffscreen()`/
 * `endOffscreen()` purely so the real painting calls (box,
 * scrollbars, underlines, cell backgrounds -- none of which are
 * gated on `draw_mode_`) land on a throwaway buffer instead of the
 * live window. This port has no offscreen-buffer primitive (see
 * `fl.draw`'s module comment). Since `pushClip()`/`popClip()` here
 * are real, reaching all the way down to the X11/Xft clip region (not
 * just bookkeeping -- see `fl.draw`'s own doc comment on
 * `restoreClip()`), a degenerate `pushClip(0, 0, 0, 0)` around the
 * measurement `draw()` call achieves the same effect with zero
 * changes needed inside `draw()` itself: everything still runs (so
 * `Mode.push`/`drag`'s hit-testing side effects still happen), it
 * just paints into a clip region with no area, so nothing is
 * actually visible on screen.
 */
module fl.help_view;

import fl.group : FlGroup;
import fl.widget : Widget, Callback;
import fl.scrollbar : Scrollbar;
import fl.slider : horSlider;
import fl.rect : Rect;
static import fl.enumerations;
import fl.enumerations : Color, Font, Fontsize, Event, CallbackReason,
    foregroundColor, backgroundColor, background2Color, selectionColor,
    times, bold, italic, helvetica, helveticaBold, courier, courierBold,
    courierItalic, symbol;
import fl.draw;
import fl.core;
import fl.menu_item : MenuItem;
import fl.menu_popup;
import fl.filename : openUri;
import fl.image : Image;
import fl.pixmap : Pixmap;
import fl.shared_image : SharedImage;

/// `Fl_Help_Func*` substitute -- see `fl.widget`'s own module comment
/// for why this project uses D delegates instead of FLTK's
/// function-pointer shape everywhere. `null` return (not `""`)
/// matches FLTK's `nullptr`-means-"leave value() unchanged"
/// contract at both of `load()`'s call sites.
alias HelpFunc = string delegate(Widget view, string uri);

// ---------------------------------------------------------------------
// Small pure helpers -- kept as free functions (not HelpView methods)
// specifically so they're headless-unittestable without a live X
// display, matching this project's "pure logic only" testing
// convention (see fl.color_chooser.d's hsv2rgb()/rgb2hsv() for
// precedent).
// ---------------------------------------------------------------------

/// atoi()/strtol()'s tolerant "parse as many leading valid digits as
/// found, default 0" behavior -- `std.conv.to!int()` throws on
/// trailing garbage (e.g. "65;"), which every call site here has (a
/// digit run immediately followed by HTML punctuation), so it can't
/// be used directly. `std.conv.parse!int()` handles the trailing-
/// garbage tolerance on its own (it consumes a leading numeric prefix
/// and simply leaves the rest unread, rather than requiring the whole
/// string to convert) but -- unlike `atoi()` -- doesn't skip leading
/// whitespace itself, so `std.string.stripLeft()` does that part.
package(fl) int atoiLike(string s)
{
    import std.conv : parse, ConvException;
    import std.string : stripLeft;

    auto rest = stripLeft(s);
    try
        return parse!int(rest);
    catch (ConvException)
        return 0;
}

private bool startsWithCI(string s, string prefix)
{
    import std.uni : sicmp;

    return s.length >= prefix.length && sicmp(s[0 .. prefix.length], prefix) == 0;
}

/// Ported from `Fl_Help_View::Impl::get_attr()`. Hand-rolled HTML
/// attribute-value parser: `p` is the raw text right after a tag name
/// (up to, but not including, the closing `>`), `name` is the
/// attribute to look up (case-insensitive). Returns `null` if the
/// attribute isn't present at all; returns `""` (non-null) for a
/// present-but-valueless ("boolean") attribute, e.g. `<HR NOSHADE>`.
package(fl) string getAttr(string p, string name)
{
    import std.ascii : isWhite;
    import std.uni : sicmp;
    import std.array : appender;

    size_t i = 0;
    while (i < p.length && p[i] != '>')
    {
        while (i < p.length && isWhite(p[i]))
            i++;
        if (i >= p.length || p[i] == '>')
            return null;

        size_t nameStart = i;
        while (i < p.length && !isWhite(p[i]) && p[i] != '=' && p[i] != '>')
            i++;
        string attrName = p[nameStart .. i];

        string value = "";
        if (i < p.length && !isWhite(p[i]) && p[i] != '>')
        {
            if (i < p.length && p[i] == '=')
                i++;

            auto buf = appender!string();
            while (i < p.length && !isWhite(p[i]) && p[i] != '>')
            {
                if (p[i] == '\'' || p[i] == '\"')
                {
                    char quote = p[i];
                    i++;
                    while (i < p.length && p[i] != quote)
                    {
                        buf.put(p[i]);
                        i++;
                    }
                    if (i < p.length && p[i] == quote)
                        i++;
                }
                else
                {
                    buf.put(p[i]);
                    i++;
                }
            }
            value = buf.data;
        }

        if (sicmp(name, attrName) == 0)
            return value;

        if (i < p.length && p[i] == '>')
            return null;
    }
    return null;
}

/// Named-color table for `getColor()`, transcribed verbatim from
/// `Fl_Help_View::Impl::get_color()`'s own local table -- deliberately
/// *not* delegated to `fl.rgb_colors`'s 490-name X11 table: several
/// names here (namely "green", "gray"/"grey", "olive", "purple",
/// "teal", "navy", "maroon") resolve to different RGB values in HTML4
/// than X11's `rgb.txt` (e.g. HTML "green" is `#008000`, X11's is
/// `#00FF00` -- X11's `#00FF00` is HTML "lime" instead), so borrowing
/// the X11 table for HTML color names would silently render wrong.
private struct NamedColor
{
    string name;
    ubyte r, g, b;
}

private static immutable NamedColor[] namedColors = [
    NamedColor("black", 0x00, 0x00, 0x00),
    NamedColor("red", 0xff, 0x00, 0x00),
    NamedColor("green", 0x00, 0x80, 0x00),
    NamedColor("yellow", 0xff, 0xff, 0x00),
    NamedColor("blue", 0x00, 0x00, 0xff),
    NamedColor("magenta", 0xff, 0x00, 0xff),
    NamedColor("fuchsia", 0xff, 0x00, 0xff),
    NamedColor("cyan", 0x00, 0xff, 0xff),
    NamedColor("aqua", 0x00, 0xff, 0xff),
    NamedColor("white", 0xff, 0xff, 0xff),
    NamedColor("gray", 0x80, 0x80, 0x80),
    NamedColor("grey", 0x80, 0x80, 0x80),
    NamedColor("lime", 0x00, 0xff, 0x00),
    NamedColor("maroon", 0x80, 0x00, 0x00),
    NamedColor("navy", 0x00, 0x00, 0x80),
    NamedColor("olive", 0x80, 0x80, 0x00),
    NamedColor("purple", 0x80, 0x00, 0x80),
    NamedColor("silver", 0xc0, 0xc0, 0xc0),
    NamedColor("teal", 0x00, 0x80, 0x80),
];

/// Ported from `Fl_Help_View::Impl::get_color()`.
package(fl) Color getColor(string n, Color c)
{
    import std.uni : sicmp;
    import std.ascii : isHexDigit;

    if (n is null || n.length == 0)
        return c;

    if (n[0] == '#')
    {
        // strtol(n+1, nullptr, 16) -- tolerant hex parse, stops at the
        // first non-hex-digit character, defaults to 0 if none found.
        int rgb = 0;
        size_t i = 1;
        while (i < n.length && isHexDigit(n[i]))
        {
            char ch = n[i];
            int digit = ch >= '0' && ch <= '9' ? ch - '0'
                : (ch >= 'a' && ch <= 'f' ? ch - 'a' + 10 : ch - 'A' + 10);
            rgb = rgb * 16 + digit;
            i++;
        }
        int r, g, b;
        if (n.length > 4)
        {
            r = (rgb >> 16) & 0xff;
            g = (rgb >> 8) & 0xff;
            b = rgb & 0xff;
        }
        else
        {
            r = ((rgb >> 8) & 0xf) * 17;
            g = ((rgb >> 4) & 0xf) * 17;
            b = (rgb & 0xf) * 17;
        }
        return rgbColor(cast(ubyte) r, cast(ubyte) g, cast(ubyte) b);
    }

    foreach (nc; namedColors)
        if (sicmp(n, nc.name) == 0)
            return rgbColor(nc.r, nc.g, nc.b);
    return c;
}

/// Ported from `Fl_Help_View::Impl::get_align()`.
package(fl) HelpView.Align getAlign(string p, HelpView.Align a)
{
    import std.uni : sicmp;

    auto v = getAttr(p, "ALIGN");
    if (v is null)
        return a;
    if (sicmp(v, "CENTER") == 0)
        return HelpView.Align.center;
    if (sicmp(v, "RIGHT") == 0)
        return HelpView.Align.right;
    return HelpView.Align.left;
}

/// Ported from `Fl_Help_View::Impl::url_scheme()`. Returns the length
/// of a leading URI scheme (e.g. "http:" or, with `skipSlashes`,
/// "http://"), or 0 if `url` doesn't start with one.
package(fl) size_t urlScheme(string url, bool skipSlashes = false)
{
    import std.ascii : isAlphaNum;

    size_t pos = 0;
    while (pos < url.length
        && (isAlphaNum(url[pos]) || url[pos] == '+' || url[pos] == '-' || url[pos] == '.'))
        pos++;
    if (pos < url.length && url[pos] == ':')
    {
        pos++;
        if (skipSlashes)
        {
            if (pos < url.length && url[pos] == '/')
            {
                pos++;
                if (pos < url.length && url[pos] == '/')
                    pos++;
            }
        }
        return pos;
    }
    return 0;
}

/// Ported from local function `to_lower()` -- ASCII-only by design,
/// matching FLTK's own comment on why (case-folding HTML anchor
/// names, which this port also only expects to be ASCII).
package(fl) string toLowerAscii(string s)
{
    import std.ascii : toLower;

    auto buf = new char[s.length];
    foreach (i, c; s)
        buf[i] = toLower(c);
    return cast(string) buf;
}

/// Ported from local function `vanilla()`, used by `find()` to skip
/// over `<...>` tag blocks while searching. `end` is an exclusive
/// upper bound (matches FLTK's `end` pointer semantics -- `p >=
/// end` FLTK). Returns the index of the next non-tag character at
/// or after `i`, or `end` if none remains / a tag was left unclosed.
package(fl) size_t vanilla(string p, size_t i, size_t end)
{
    if (i >= p.length || i >= end)
        return end;
    for (;;)
    {
        if (p[i] != '<')
            return i;
        while (i < p.length && i < end && p[i] != '>')
            i++;
        i++;
        if (i >= p.length || i >= end)
            return end;
    }
}

/// Ported from local function `command()`: packs up to the first 4
/// significant characters of `cmd` (lowercased) into a big-endian
/// `uint`, stopping early at `'>'`/space/end-of-string -- returns 0 if
/// a 5th significant character exists (used by `copy()` to match
/// plaintext-conversion tags via `CMD()`-built constants).
package(fl) uint command(string cmd)
{
    import std.ascii : toLower;

    char at(size_t i) => i < cmd.length ? cmd[i] : '\0';
    bool stop(char c) => c == '>' || c == ' ' || c == '\0';

    uint ret = cast(uint) toLower(at(0)) << 24;
    char c = at(1);
    if (stop(c))
        return ret;
    ret |= cast(uint) toLower(c) << 16;
    c = at(2);
    if (stop(c))
        return ret;
    ret |= cast(uint) toLower(c) << 8;
    c = at(3);
    if (stop(c))
        return ret;
    ret |= cast(uint) toLower(c);
    c = at(4);
    if (stop(c))
        return ret;
    return 0;
}

package(fl) uint CMD(char a, char b, char c, char d)
{
    return (cast(uint) a << 24) | (cast(uint) b << 16) | (cast(uint) c << 8) | cast(uint) d;
}

/// Named-HTML-entity table for `quoteChar()`, transcribed verbatim
/// from local function `quote_char()`'s own table (`&name;` forms
/// only -- numeric `&#NN;`/`&#xNN;` forms are handled separately,
/// without a table lookup). `name` includes the trailing `;`.
private struct EntityEntry
{
    string name;
    int code;
}

private static immutable EntityEntry[] entityTable = [
    EntityEntry("Aacute;", 193), EntityEntry("aacute;", 225),
    EntityEntry("Acirc;", 194), EntityEntry("acirc;", 226),
    EntityEntry("acute;", 180), EntityEntry("AElig;", 198),
    EntityEntry("aelig;", 230), EntityEntry("Agrave;", 192),
    EntityEntry("agrave;", 224), EntityEntry("amp;", '&'),
    EntityEntry("Aring;", 197), EntityEntry("aring;", 229),
    EntityEntry("Atilde;", 195), EntityEntry("atilde;", 227),
    EntityEntry("Auml;", 196), EntityEntry("auml;", 228),
    EntityEntry("brvbar;", 166), EntityEntry("bull;", 0x2022),
    EntityEntry("Ccedil;", 199), EntityEntry("ccedil;", 231),
    EntityEntry("cedil;", 184), EntityEntry("cent;", 162),
    EntityEntry("copy;", 169), EntityEntry("curren;", 164),
    EntityEntry("dagger;", 0x2020), EntityEntry("deg;", 176),
    EntityEntry("divide;", 247), EntityEntry("Eacute;", 201),
    EntityEntry("eacute;", 233), EntityEntry("Ecirc;", 202),
    EntityEntry("ecirc;", 234), EntityEntry("Egrave;", 200),
    EntityEntry("egrave;", 232), EntityEntry("ETH;", 208),
    EntityEntry("eth;", 240), EntityEntry("Euml;", 203),
    EntityEntry("euml;", 235), EntityEntry("euro;", 0x20ac),
    EntityEntry("frac12;", 189), EntityEntry("frac14;", 188),
    EntityEntry("frac34;", 190), EntityEntry("gt;", '>'),
    EntityEntry("Iacute;", 205), EntityEntry("iacute;", 237),
    EntityEntry("Icirc;", 206), EntityEntry("icirc;", 238),
    EntityEntry("iexcl;", 161), EntityEntry("Igrave;", 204),
    EntityEntry("igrave;", 236), EntityEntry("iquest;", 191),
    EntityEntry("Iuml;", 207), EntityEntry("iuml;", 239),
    EntityEntry("laquo;", 171), EntityEntry("lt;", '<'),
    EntityEntry("macr;", 175), EntityEntry("micro;", 181),
    EntityEntry("middot;", 183), EntityEntry("nbsp;", ' '),
    EntityEntry("ndash;", 0x2013), EntityEntry("not;", 172),
    EntityEntry("Ntilde;", 209), EntityEntry("ntilde;", 241),
    EntityEntry("Oacute;", 211), EntityEntry("oacute;", 243),
    EntityEntry("Ocirc;", 212), EntityEntry("ocirc;", 244),
    EntityEntry("Ograve;", 210), EntityEntry("ograve;", 242),
    EntityEntry("ordf;", 170), EntityEntry("ordm;", 186),
    EntityEntry("Oslash;", 216), EntityEntry("oslash;", 248),
    EntityEntry("Otilde;", 213), EntityEntry("otilde;", 245),
    EntityEntry("Ouml;", 214), EntityEntry("ouml;", 246),
    EntityEntry("para;", 182), EntityEntry("permil;", 0x2030),
    EntityEntry("plusmn;", 177), EntityEntry("pound;", 163),
    EntityEntry("quot;", '\"'), EntityEntry("raquo;", 187),
    EntityEntry("reg;", 174), EntityEntry("sect;", 167),
    EntityEntry("shy;", 173), EntityEntry("sup1;", 185),
    EntityEntry("sup2;", 178), EntityEntry("sup3;", 179),
    EntityEntry("szlig;", 223), EntityEntry("THORN;", 222),
    EntityEntry("thorn;", 254), EntityEntry("times;", 215),
    EntityEntry("trade;", 0x2122), EntityEntry("Uacute;", 218),
    EntityEntry("uacute;", 250), EntityEntry("Ucirc;", 219),
    EntityEntry("ucirc;", 251), EntityEntry("Ugrave;", 217),
    EntityEntry("ugrave;", 249), EntityEntry("uml;", 168),
    EntityEntry("Uuml;", 220), EntityEntry("uuml;", 252),
    EntityEntry("Yacute;", 221), EntityEntry("yacute;", 253),
    EntityEntry("yen;", 165), EntityEntry("Yuml;", 0x0178),
    EntityEntry("yuml;", 255),
];

/// Ported from local function `quote_char()`. `p` is the text right
/// after the `&` (so `&amp;` calls this with `"amp;..."`). Returns the
/// decoded Unicode code point, or -1 if `p` isn't a recognized entity
/// (including: no `;` anywhere in the rest of the document at all --
/// matches FLTK's own `strchr(p, ';')` full-remaining-text scan).
package(fl) int quoteChar(string p)
{
    import std.ascii : isDigit, isHexDigit;
    import std.algorithm.searching : canFind, startsWith;

    if (!p.canFind(';'))
        return -1;

    if (p.length > 0 && p[0] == '#')
    {
        if (p.length > 1 && (p[1] == 'x' || p[1] == 'X'))
        {
            int val = 0;
            size_t j = 2;
            while (j < p.length && isHexDigit(p[j]))
            {
                char ch = p[j];
                int digit = ch >= '0' && ch <= '9' ? ch - '0'
                    : (ch >= 'a' && ch <= 'f' ? ch - 'a' + 10 : ch - 'A' + 10);
                val = val * 16 + digit;
                j++;
            }
            return val;
        }
        else
        {
            int val = 0;
            size_t j = 1;
            while (j < p.length && isDigit(p[j]))
            {
                val = val * 10 + (p[j] - '0');
                j++;
            }
            return val;
        }
    }

    foreach (e; entityTable)
        if (p.startsWith(e.name))
            return e.code;

    return -1;
}

/**
 * HTML-subset viewer widget -- see this module's own top comment for
 * scope/staging and the deliberate `Impl`-collapse/offscreen-buffer
 * deviations from FLTK.
 */
class HelpView : FlGroup
{
    // Widget.size(int,int) is hidden by this class's own 0-arg
    // size() getter below, and FlGroup.find(Widget) is hidden by
    // find(string,int) -- both need re-exposing, exactly as FLTK
    // itself has to write `void size(int W,int H) { Fl_Widget::
    // size(W,H); }` inline for the same reason (a derived class
    // introducing any overload of a name hides the base class's other
    // overloads, in both C++ and D).
    alias size = FlGroup.size;
    alias find = FlGroup.find;

    /** This text may be customized at run-time. */
    static string copyMenuText = "Copy";

    /// Ported from `Fl_Help_View::Impl::Align` (`enum class Align`).
    enum Align
    {
        right = -1,
        center = 0,
        left = 1,
    }

    /// Ported from `Fl_Help_View::Impl::Mode`. `draw` is normal
    /// painting; `push`/`drag` are the measurement passes described in
    /// this module's own top comment (draw() re-entered with painting
    /// suppressed via a degenerate pushClip(), to find which character
    /// offset is under the mouse).
    enum Mode
    {
        draw,
        push,
        drag,
    }

    private struct MarginStack
    {
        private int[] margins_ = [4];

        void clear()
        {
            margins_ = [4];
        }

        int current() const => margins_[$ - 1];

        int pop()
        {
            if (margins_.length > 1)
                margins_ = margins_[0 .. $ - 1];
            return margins_[$ - 1];
        }

        int push(int indent)
        {
            int xx = current() + indent;
            margins_ ~= xx;
            return xx;
        }
    }

    /// Ported from `Fl_Help_View::Impl::Edit_Buffer` (`public
    /// std::string` FLTK, purely to reuse std::string's own
    /// growable-buffer machinery -- no inheritance trick needed here).
    private struct EditBuffer
    {
        private char[] buf_;

        void clear()
        {
            buf_.length = 0;
        }

        size_t size() const => buf_.length;

        string str() const => buf_.idup;

        void opOpAssign(string op : "~")(char c)
        {
            buf_ ~= c;
        }

        /// UTF-8-encodes and appends one Unicode code point.
        void add(dchar ucs)
        {
            import std.utf : encode;

            char[4] tmp;
            size_t n = encode(tmp, ucs);
            buf_ ~= tmp[0 .. n];
        }

        /// Case-insensitive comparison against the *entire* buffer
        /// contents (used to match tag names, e.g. `buf.cmp("BR")`).
        bool cmp(string s) const
        {
            import std.uni : sicmp;

            return sicmp(cast(string) buf_, s) == 0;
        }

        /// Safe indexed access -- returns '\0' past the end, matching
        /// how FLTK's C-string-backed buffer always has a null
        /// terminator one past its last real character (relied on by
        /// several call sites, e.g. `buf[1]` on a 1-char buffer).
        char opIndex(size_t i) const => i < buf_.length ? buf_[i] : '\0';

        double width() const => fl.draw.width(cast(string) buf_);
    }

    /// Ported from `Fl_Help_View::Impl::Text_Block`. `start`/`end` are
    /// offsets into `value_` (not pointers/slices -- unifies with
    /// `selectionFirst_`/`selectionLast_`, which FLTK's own
    /// comments already describe as offsets into `value_` too).
    private struct TextBlock
    {
        size_t start, end;
        ubyte border;
        Color bgcolor;
        int x, y, w, h;
        // Left starting position for each line -- FLTK caps at 32
        // entries (line[32]) and silently stops advancing past index
        // 31 (do_align()'s `if (line < 31) line++`); a block with more
        // than 32 lines just re-uses line[31] for everything past it.
        // Ported faithfully, not "fixed" -- see FLTK_ISSUES.md.
        int[32] line;
        int ol;
        int olNum;
    }

    /// Ported from `Fl_Help_View::Impl::Link`. A class (not a struct)
    /// deliberately -- `findLink()`/link_list_ need nullable, shared
    /// reference semantics (FLTK: `std::shared_ptr<Link>`), and
    /// `TextBlock`'s array-index approach doesn't apply here since
    /// nothing ever holds a raw pointer into `linkList_` across a
    /// mutation of it (unlike `blocks_`, see `addBlock()`'s own note).
    private static class Link
    {
        string filename_, target;
        Rect box;
    }

    private struct FontStyle
    {
        Font f;
        Fontsize s;
        Color c;
    }

    private struct FontStack
    {
        private FontStyle[] elts_;

        void init_(Font f, Fontsize s, Color c)
        {
            elts_ = [];
            push(f, s, c);
        }

        void top(out Font f, out Fontsize s, out Color c) const
        {
            auto e = elts_[$ - 1];
            f = e.f;
            s = e.s;
            c = e.c;
        }

        void push(Font f, Fontsize s, Color c)
        {
            elts_ ~= FontStyle(f, s, c);
            fl_font(f, s);
            fl_color(c);
        }

        /// If only one element remains, it is *not* popped -- that
        /// element is re-applied instead, matching FLTK exactly.
        void pop(out Font f, out Fontsize s, out Color c)
        {
            if (elts_.length > 1)
                elts_ = elts_[0 .. $ - 1];
            top(f, s, c);
            fl_font(f, s);
            fl_color(c);
        }

        size_t count() const => elts_.length;
    }

    // ---- HTML source and raw data ----

    private string value_;
    private string directory_;
    private string filename_;

    /// Ported from `Fl_Help_View::Impl::get_image()`'s own `initial_load`
    /// -- a process-wide `static` FLTK (see that function's own
    /// large doc comment for the full reasoning), an instance field
    /// here instead (no reason to share it across every `HelpView` in
    /// the process, and an instance field avoids the global-state
    /// hazard entirely). `true` only while `format()` is running as a
    /// direct result of `value()`/`load()` setting brand new content --
    /// `getImage()` uses `SharedImage.get()` (a real load, bumping the
    /// refcount for the document's lifetime) in that window, and
    /// `SharedImage.find()` (cache-lookup only, net-zero refcount) at
    /// every other call site (`resize()`, `draw()`, `textcolor()`/etc.
    /// re-layouts) -- avoids both unnecessary I/O and refcount churn on
    /// every redraw.
    private bool initialLoad_;

    // ---- HTML document data ----

    private string title_;
    private FontStack fstack_;
    private TextBlock[] blocks_;
    private Link[] linkList_;
    private int[string] targetLineMap_;

    private int topline_;
    private int leftline_;
    private int size_;
    private int hsize_;

    // ---- Default visual attributes ----

    private Color defcolor_ = foregroundColor;
    private Color bgcolor_ = backgroundColor;
    private Color textcolor_ = foregroundColor;
    private Color linkcolor_ = fl.enumerations.selectionColor;
    private Font textfont_ = times;
    private Fontsize textsize_ = 12;

    // ---- Text selection and mouse handling ----

    private Mode selectionMode_ = Mode.draw;
    private bool selected_;
    private int selectionFirst_;
    private int selectionLast_;
    private Color tmpSelectionColor_;
    private Color selectionTextColor_;

    // Genuinely process-wide statics FLTK (its own comment says
    // so -- "we need them only once during mouse events") -- same
    // class of thing as fl.slider's `offcenter`/fl.roller's `ipos`,
    // just needed across more than one method here so a function-local
    // `static` (this project's usual idiom for that pattern) won't
    // reach; a class-static is the direct D equivalent of FLTK's
    // C++ `static` data member.
    private static int selectionPushFirst_, selectionPushLast_;
    private static int selectionDragFirst_, selectionDragLast_;
    private static Mode drawMode_ = Mode.draw;
    private static int currentPos_;

    // ---- Callback ----

    private HelpFunc linkFunc_;

    // ---- Scrollbars ----

    private Scrollbar scrollbar_, hscrollbar_;
    private int scrollbarSize_;

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);

        color(background2Color, fl.enumerations.selectionColor);

        auto ss = fl.core.scrollbarSize();
        scrollbar_ = new Scrollbar(x + w - ss, y, ss, h - ss);
        scrollbar_.value(0, h, 0, 1);
        scrollbar_.step(8.0);
        scrollbar_.show();
        scrollbar_.callback((wd) { topline(cast(int) scrollbar_.value()); });

        hscrollbar_ = new Scrollbar(x, y + h - ss, w - ss, ss);
        hscrollbar_.value(0, w, 0, 1);
        hscrollbar_.step(8.0);
        hscrollbar_.show();
        hscrollbar_.type(horSlider);
        hscrollbar_.callback((wd) { leftline(cast(int) hscrollbar_.value()); });

        end();

        resize(x, y, w, h);
    }

    Scrollbar scrollbar() => scrollbar_;
    Scrollbar hscrollbar() => hscrollbar_;

    // ---- HTML source and raw data, getter ----

    /// Ported from `Fl_Help_View::Impl::free_data()`. Walks the whole
    /// document releasing any loaded `<IMG>` images before dropping
    /// `value_`, matching FLTK: each
    /// image an initial `format()` pass loaded via `getImage()`'s
    /// `SharedImage.get()` holds one permanent reference for the
    /// document's lifetime, released here exactly once. Uses a
    /// deliberately minimal standalone tag scan (matching FLTK's
    /// own simple linear `<...>`-finding loop here, *not* the full
    /// tokenizer `format()`/`draw()` use) since nothing else about the
    /// markup matters for this pass.
    private void freeData()
    {
        if (value_ !is null)
        {
            import std.ascii : isWhite;
            import std.string : indexOf;
            import std.uni : sicmp;

            size_t i = 0;
            while (i < value_.length)
            {
                if (value_[i] == '<')
                {
                    i++;
                    if (i + 3 <= value_.length && value_[i .. i + 3] == "!--")
                    {
                        i += 3;
                        auto closePos = value_[i .. $].indexOf("-->");
                        if (closePos >= 0) { i = i + closePos + 3; continue; }
                        else break;
                    }

                    size_t tagStart = i;
                    while (i < value_.length && value_[i] != '>' && !isWhite(value_[i])) i++;
                    string tag = value_[tagStart .. i];

                    size_t attrsStart = i;
                    while (i < value_.length && value_[i] != '>') i++;
                    string attrs = value_[attrsStart .. i];
                    if (i < value_.length) i++; // skip '>'

                    if (sicmp(tag, "IMG") == 0)
                    {
                        auto src = getAttr(attrs, "SRC");
                        if (src !is null)
                        {
                            auto img = getImage(src, 0, 0);
                            if (img !is brokenImage())
                            {
                                auto shared_ = cast(SharedImage) img;
                                if (shared_ !is null) shared_.release();
                            }
                        }
                    }
                }
                else i++;
            }
        }

        value_ = null;
        blocks_ = null;
        linkList_ = null;
        targetLineMap_ = null;
    }

    // Verbatim transcription of FLTK's own `broken_xpm[]` (src/
    // Fl_Help_View.cxx) -- the fallback icon `getImage()` returns for a
    // missing/unloadable `<IMG SRC="...">`, or when `linkFunc_` rejects
    // the resolved URL.
    private static immutable string[] brokenXpm = [
        "16 24 4 1",
        "@ c #000000",
        "  c #ffffff",
        "+ c none",
        "x c #ff0000",
        "@@@@@@@+++++++++",
        "@    @++++++++++",
        "@   @+++++++++++",
        "@   @++@++++++++",
        "@    @@+++++++++",
        "@     @+++@+++++",
        "@     @++@@++++@",
        "@ xxx  @@  @++@@",
        "@  xxx    xx@@ @",
        "@   xxx  xxx   @",
        "@    xxxxxx    @",
        "@     xxxx     @",
        "@    xxxxxx    @",
        "@   xxx  xxx   @",
        "@  xxx    xxx  @",
        "@ xxx      xxx @",
        "@              @",
        "@              @",
        "@              @",
        "@              @",
        "@              @",
        "@              @",
        "@              @",
        "@@@@@@@@@@@@@@@@",
    ];
    private Pixmap brokenImage_;
    private Pixmap brokenImage()
    {
        if (brokenImage_ is null) brokenImage_ = new Pixmap(brokenXpm);
        return brokenImage_;
    }

    /**
     * Ported from `Fl_Help_View::Impl::get_image()`.
     *
     * Resolves `name` (a local filename or URL) against `directory_`/
     * `linkFunc_` -- the exact same URL-resolution shape as
     * `followLink()`'s own (FLTK doesn't share the two either, so
     * this doesn't either) -- then loads it via `fl.shared_image`:
     * `SharedImage.get()` during the true initial load (`initialLoad_`,
     * see its own doc comment), `SharedImage.find()` everywhere else.
     * `find()`'s result is `release()`d immediately either way but
     * still returned/used -- safe, matching FLTK's own refcount
     * contract exactly: the *initial* `get()` call is what actually
     * keeps the image alive for the document's lifetime, so every
     * later `find()`+`release()` pair nets to zero, a transient "peek"
     * at the already-cached image. Returns `brokenImage()` (matching
     * FLTK's own fixed `broken_image` sentinel) if `name` is empty,
     * `linkFunc_` rejects the resolved URL, or nothing could be loaded.
     */
    private Image getImage(string name, int W, int H)
    {
        import std.file : getcwd;
        import std.string : startsWith;

        if (name.length == 0) return brokenImage();

        string url;
        auto directoryScheme = urlScheme(directory_);
        auto nameScheme = urlScheme(name);

        if (directoryScheme > 0 && nameScheme == 0)
        {
            if (name[0] == '/')
                url = directory_[0 .. directoryScheme] ~ name;
            else
                url = directory_ ~ "/" ~ name;
        }
        else if (name[0] != '/' && nameScheme == 0)
        {
            if (directory_.length > 0)
                url = directory_ ~ "/" ~ name;
            else
                url = "file:" ~ getcwd() ~ "/" ~ name;
        }
        else
            url = name;

        if (linkFunc_ !is null)
        {
            auto n = linkFunc_(this, url);
            if (n is null) return brokenImage();
            url = n;
        }

        if (url.length == 0) return brokenImage();

        if (url.startsWith("file:"))
            url = url[5 .. $];

        Image img;
        if (initialLoad_)
        {
            img = SharedImage.get(url, W, H);
        }
        else
        {
            auto found = SharedImage.find(url, W, H);
            if (found !is null) found.release();
            img = found;
        }

        return img !is null ? img : brokenImage();
    }

    private Link findLink(int xx, int yy)
    {
        foreach (link; linkList_)
            if (link.box.contains(xx, yy))
                return link;
        return null;
    }

    // ---- HTML interpretation and formatting ----

    /// Ported from `Fl_Help_View::Impl::add_block()`. Returns the
    /// *index* of the new block in `blocks_`, not a pointer/reference
    /// to it -- FLTK's own `Text_Block *temp = &blocks_.back();`
    /// is a raw pointer into a `std::vector` that FLTK itself must
    /// re-fetch after every subsequent `push_back()` (real risk of
    /// reallocation moving it); an index has no such hazard against a
    /// D dynamic array's `~=`.
    private size_t addBlock(size_t s, int xx, int yy, int ww, int hh, ubyte border = 0)
    {
        TextBlock t;
        t.start = s;
        t.end = s;
        t.x = xx;
        t.y = yy;
        t.w = ww;
        t.h = hh;
        t.border = border;
        t.bgcolor = bgcolor_;
        blocks_ ~= t;
        return blocks_.length - 1;
    }

    private void addLink(string link, int xx, int yy, int ww, int hh)
    {
        import std.string : indexOf;

        auto l = new Link();
        l.box = Rect(xx, yy, ww, hh);
        auto hash = link.indexOf('#');
        if (hash >= 0)
        {
            l.filename_ = link[0 .. hash];
            l.target = link[hash + 1 .. $];
        }
        else
        {
            l.filename_ = link;
            l.target = "";
        }
        linkList_ ~= l;
    }

    private void addTarget(string n, int yy)
    {
        targetLineMap_[toLowerAscii(n)] = yy;
    }

    /// Ported from `Fl_Help_View::Impl::do_align()`.
    private int doAlign(size_t blockIdx, int line, int xx, Align a, ref int l)
    {
        int offset;
        final switch (a)
        {
        case Align.right:
            offset = blocks_[blockIdx].w - xx;
            break;
        case Align.center:
            offset = (blocks_[blockIdx].w - xx) / 2;
            break;
        case Align.left:
            offset = 0;
            break;
        }

        blocks_[blockIdx].line[line] = blocks_[blockIdx].x + offset;

        if (line < 31)
            line++;

        while (l < cast(int) linkList_.length)
        {
            linkList_[l].box.x(linkList_[l].box.x() + offset);
            l++;
        }

        return line;
    }

    private void initfont(out Font f, out Fontsize s, out Color c)
    {
        f = textfont_;
        s = textsize_;
        c = textcolor_;
        fstack_.init_(f, s, c);
    }

    private void pushfont(Font f, Fontsize s)
    {
        fstack_.push(f, s, textcolor_);
    }

    private void pushfont(Font f, Fontsize s, Color c)
    {
        fstack_.push(f, s, c);
    }

    private void popfont(out Font f, out Fontsize s, out Color c)
    {
        fstack_.pop(f, s, c);
    }

    /// Ported from `Fl_Help_View::Impl::get_length()` -- needs
    /// instance state (`hsize_`/`scrollbarSize_`), unlike get_attr()/
    /// get_align()/get_color(), so it stays a method rather than a
    /// free function.
    private int getLength(string l) const
    {
        if (l.length == 0)
            return 0;
        int val = atoiLike(l);
        if (l[$ - 1] == '%')
        {
            if (val > 100)
                val = 100;
            else if (val < 0)
                val = 0;
            int scrollsize = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
            val = val * (hsize_ - scrollsize) / 100;
        }
        return val;
    }

    /**
     * Ported from `Fl_Help_View::Impl::format()`. `<TABLE>`/`<TR>`/
     * `<TD>`/`<TH>` are real now (Milestone 2, see this module's top
     * comment) -- `row` (0 == not currently inside a `<TR>`, matching
     * FLTK's own "block 0 is never a real row" sentinel) and
     * `cells`/`columns` (growable D arrays, not FLTK's fixed
     * `int[MAX_COLUMNS]`) track the table currently being laid out;
     * `formatTable()` is the column-width pre-scan a `<TABLE>` tag
     * calls into before laying out its rows. `<IMG>` reserves a fixed
     * 16x24 placeholder box (matches FLTK's own `broken_image`
     * fallback exactly, since `fl.image` never loads anything real --
     * see get_image()'s FLTK doc comment).
     */
    private void format()
    {
        import fl.enumerations : Boxtype, blue;
        import std.ascii : isWhite, isDigit, toLower;
        import std.array : appender;
        import std.string : indexOf;
        import std.math : pow;

        Boxtype b = box() ? box() : Boxtype.downBox;

        int scrollsize = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
        hsize_ = w() - scrollsize - boxDw(b);

        // Ported verbatim from FLTK's own (odd) placement: OL_num
        // is declared *outside* the retry loop below, so a mid-list
        // retry (hsize_ growing because a word didn't fit) does not
        // reset it -- this looks like it could be an FLTK
        // list-numbering quirk across retries; not chased further
        // here, ported bug-for-bug rather than silently changed.
        int[] olStack = [-1];
        Color tc, rc;

        bool done = false;
        while (!done)
        {
            done = true;
            blocks_ = null;
            linkList_ = null;
            targetLineMap_ = null;
            size_ = 0;
            bgcolor_ = color();
            textcolor_ = this.textcolor();
            linkcolor_ = contrast(blue, color());
            tc = rc = bgcolor_;

            title_ = "Untitled";

            if (value_ is null)
                return;

            Font font;
            Fontsize fsize;
            Color fcolor;
            initfont(font, fsize, fcolor);

            int line = 0;
            int links = 0;
            MarginStack margins;
            margins.clear();
            int xx = 4;
            int yy = fsize + 2;
            int ww = 0;
            int hh = 0;
            size_t block = addBlock(0, xx, yy, hsize_, 0);
            int head = 0;
            int pre = 0;
            Align talign = Align.left;
            Align newalign = Align.left;
            int needspace = 0;
            string linkdest = "";

            // Table layout state -- see the "TABLE" branch below and
            // formatTable() for the pre-pass that computes columns[].
            size_t row = 0; // block index of the current <TR>, 0 == not in a row
            int column = 0;
            ubyte border = 0;
            int tableOffset = 0;
            int tableWidth = 0;
            int[] columns;
            // Block index of each column's current cell in the active
            // row, 0 == unset (block 0 is always the initial pre-loop
            // block, never a real <TD>, so 0 is a safe sentinel --
            // matches FLTK's `memset(cells, 0, sizeof(cells))`).
            // Growable, replacing FLTK's `int cells[MAX_COLUMNS]`
            // (a 200-column cap) -- see formatTable()'s own comment
            // for why this port dissolves that cap.
            int[] cells;

            EditBuffer buf;
            size_t i = 0;

            while (i < value_.length)
            {
                char c = value_[i];

                // End of word?
                if ((c == '<' || isWhite(c)) && buf.size() > 0)
                {
                    ww = cast(int) buf.width();

                    if (!head && !pre)
                    {
                        if (ww > hsize_)
                        {
                            hsize_ = ww;
                            done = false;
                            break;
                        }

                        if (needspace && xx > blocks_[block].x)
                            ww += cast(int) width(" ");

                        if ((xx + ww) > blocks_[block].w)
                        {
                            line = doAlign(block, line, xx, newalign, links);
                            xx = blocks_[block].x;
                            yy += hh;
                            blocks_[block].h += hh;
                            hh = 0;
                        }

                        if (linkdest.length)
                            addLink(linkdest, xx, yy - fsize, ww, fsize);

                        xx += ww;
                        if ((fsize + 2) > hh)
                            hh = fsize + 2;

                        needspace = 0;
                    }
                    else if (pre)
                    {
                        if (linkdest.length)
                            addLink(linkdest, xx, yy - hh, ww, hh);

                        xx += ww;
                        if ((fsize + 2) > hh)
                            hh = fsize + 2;

                        while (i < value_.length && isWhite(value_[i]))
                        {
                            if (value_[i] == '\n')
                            {
                                if (xx > hsize_)
                                    break;

                                line = doAlign(block, line, xx, newalign, links);
                                xx = blocks_[block].x;
                                yy += hh;
                                blocks_[block].h += hh;
                                hh = fsize + 2;
                            }
                            else
                                xx += cast(int) width(" ");

                            if ((fsize + 2) > hh)
                                hh = fsize + 2;

                            i++;
                        }

                        if (xx > hsize_)
                        {
                            hsize_ = xx;
                            done = false;
                            break;
                        }

                        needspace = 0;
                    }
                    else
                    {
                        while (i < value_.length && isWhite(value_[i]))
                            i++;
                    }

                    buf.clear();
                }

                if (i < value_.length && value_[i] == '<')
                {
                    size_t start = i;
                    i++;

                    if (i + 3 <= value_.length && value_[i .. i + 3] == "!--")
                    {
                        i += 3;
                        auto closePos = value_[i .. $].indexOf("-->");
                        if (closePos >= 0)
                        {
                            i = i + closePos + 3;
                            continue;
                        }
                        else
                            break;
                    }

                    buf.clear();
                    while (i < value_.length && value_[i] != '>' && !isWhite(value_[i]))
                    {
                        buf ~= value_[i];
                        i++;
                    }

                    size_t attrsStart = i;
                    while (i < value_.length && value_[i] != '>')
                        i++;
                    string attrs = value_[attrsStart .. i];

                    if (i < value_.length && value_[i] == '>')
                        i++;

                    if (buf.cmp("HEAD"))
                        head = 1;
                    else if (buf.cmp("/HEAD"))
                        head = 0;
                    else if (buf.cmp("TITLE"))
                    {
                        auto tbuf = appender!string();
                        while (i < value_.length && value_[i] != '<')
                        {
                            tbuf.put(value_[i]);
                            i++;
                        }
                        title_ = tbuf.data;
                        buf.clear();
                    }
                    else if (buf.cmp("A"))
                    {
                        auto nameAttr = getAttr(attrs, "NAME");
                        if (nameAttr !is null)
                            addTarget(nameAttr, yy - fsize - 2);
                        auto hrefAttr = getAttr(attrs, "HREF");
                        if (hrefAttr !is null)
                            linkdest = hrefAttr;
                    }
                    else if (buf.cmp("/A"))
                        linkdest = "";
                    else if (buf.cmp("BODY"))
                    {
                        bgcolor_ = getColor(getAttr(attrs, "BGCOLOR"), color());
                        textcolor_ = getColor(getAttr(attrs, "TEXT"), this.textcolor());
                        linkcolor_ = getColor(getAttr(attrs, "LINK"), contrast(blue, color()));
                    }
                    else if (buf.cmp("BR"))
                    {
                        line = doAlign(block, line, xx, newalign, links);
                        xx = blocks_[block].x;
                        blocks_[block].h += hh;
                        yy += hh;
                        hh = 0;
                    }
                    else if (buf.cmp("CENTER") || buf.cmp("P")
                        || buf.cmp("H1") || buf.cmp("H2") || buf.cmp("H3")
                        || buf.cmp("H4") || buf.cmp("H5") || buf.cmp("H6")
                        || buf.cmp("UL") || buf.cmp("OL") || buf.cmp("DL")
                        || buf.cmp("LI") || buf.cmp("DD") || buf.cmp("DT")
                        || buf.cmp("HR") || buf.cmp("PRE") || buf.cmp("TABLE"))
                    {
                        blocks_[block].end = start;
                        line = doAlign(block, line, xx, newalign, links);
                        newalign = buf.cmp("CENTER") ? Align.center : Align.left;
                        xx = blocks_[block].x;
                        blocks_[block].h += hh;

                        if (buf.cmp("OL"))
                        {
                            int olNum = 1;
                            auto startAttr = getAttr(attrs, "START");
                            if (startAttr !is null)
                            {
                                olNum = atoiLike(startAttr);
                                if (olNum < 0)
                                    olNum = 1;
                            }
                            olStack ~= olNum;
                        }
                        else if (buf.cmp("UL"))
                            olStack ~= -1;

                        if (buf.cmp("UL") || buf.cmp("OL") || buf.cmp("DL"))
                        {
                            blocks_[block].h += fsize + 2;
                            xx = margins.push(4 * fsize);
                        }
                        else if (buf.cmp("TABLE"))
                        {
                            auto borderAttr = getAttr(attrs, "BORDER");
                            border = borderAttr !is null ? cast(ubyte) atoiLike(borderAttr) : 0;

                            tc = rc = getColor(getAttr(attrs, "BGCOLOR"), bgcolor_);

                            blocks_[block].h += fsize + 2;

                            formatTable(tableWidth, columns, start);

                            if ((xx + tableWidth) > hsize_)
                            {
                                hsize_ = xx + tableWidth;
                                done = false;
                                break;
                            }

                            final switch (getAlign(attrs, talign))
                            {
                            case Align.left:
                                tableOffset = 0;
                                break;
                            case Align.center:
                                tableOffset = (hsize_ - tableWidth) / 2 - textsize_;
                                break;
                            case Align.right:
                                tableOffset = hsize_ - tableWidth - textsize_;
                                break;
                            }

                            column = 0;
                        }

                        bool isHn = toLower(buf[0]) == 'h' && isDigit(buf[1]);
                        if (isHn)
                        {
                            font = helveticaBold;
                            fsize = textsize_ + '7' - buf[1];
                        }
                        else if (buf.cmp("DT"))
                        {
                            font = textfont_ | italic;
                            fsize = textsize_;
                        }
                        else if (buf.cmp("PRE"))
                        {
                            font = courier;
                            fsize = textsize_;
                            pre = 1;
                        }
                        else
                        {
                            font = textfont_;
                            fsize = textsize_;
                        }

                        pushfont(font, fsize);

                        yy = blocks_[block].y + blocks_[block].h;
                        hh = 0;

                        if (isHn || buf.cmp("DD") || buf.cmp("DT") || buf.cmp("P"))
                            yy += fsize + 2;
                        else if (buf.cmp("HR"))
                        {
                            hh += 2 * fsize;
                            yy += fsize;
                        }

                        block = row ? addBlock(start, xx, yy, blocks_[block].w, 0)
                                    : addBlock(start, xx, yy, hsize_, 0);

                        if (buf.cmp("LI"))
                        {
                            blocks_[block].ol = 0;
                            if (olStack.length && olStack[$ - 1] >= 0)
                            {
                                blocks_[block].ol = 1;
                                blocks_[block].olNum = olStack[$ - 1];
                                olStack[$ - 1]++;
                            }
                        }

                        needspace = 0;
                        line = 0;

                        if (buf.cmp("CENTER"))
                            newalign = talign = Align.center;
                        else
                            newalign = getAlign(attrs, talign);
                    }
                    else if (buf.cmp("/CENTER") || buf.cmp("/P")
                        || buf.cmp("/H1") || buf.cmp("/H2") || buf.cmp("/H3")
                        || buf.cmp("/H4") || buf.cmp("/H5") || buf.cmp("/H6")
                        || buf.cmp("/PRE") || buf.cmp("/UL") || buf.cmp("/OL") || buf.cmp("/DL")
                        || buf.cmp("/TABLE"))
                    {
                        line = doAlign(block, line, xx, newalign, links);
                        xx = blocks_[block].x;
                        blocks_[block].end = i;

                        if (buf.cmp("/OL") || buf.cmp("/UL"))
                        {
                            if (olStack.length)
                                olStack = olStack[0 .. $ - 1];
                        }

                        if (buf.cmp("/UL") || buf.cmp("/OL") || buf.cmp("/DL"))
                        {
                            xx = margins.pop();
                            blocks_[block].h += fsize + 2;
                        }
                        else if (buf.cmp("/TABLE"))
                        {
                            blocks_[block].h += fsize + 2;
                            xx = margins.current();
                        }
                        else if (buf.cmp("/PRE"))
                        {
                            pre = 0;
                            hh = 0;
                        }
                        else if (buf.cmp("/CENTER"))
                            talign = Align.left;

                        popfont(font, fsize, fcolor);

                        while (i < value_.length && isWhite(value_[i]))
                            i++;

                        blocks_[block].h += hh;
                        yy += hh;

                        if (toLower(buf[2]) == 'l')
                            yy += fsize + 2;

                        block = row ? addBlock(i, xx, yy, blocks_[block].w, 0)
                                    : addBlock(i, xx, yy, hsize_, 0);

                        needspace = 0;
                        hh = 0;
                        line = 0;
                        newalign = talign;
                    }
                    else if (buf.cmp("TR"))
                    {
                        blocks_[block].end = start;
                        line = doAlign(block, line, xx, newalign, links);
                        xx = blocks_[block].x;
                        blocks_[block].h += hh;

                        if (row)
                        {
                            yy = blocks_[row].y + blocks_[row].h;
                            foreach (idx; row + 1 .. block + 1)
                                if ((blocks_[idx].y + blocks_[idx].h) > yy)
                                    yy = blocks_[idx].y + blocks_[idx].h;

                            block = row;
                            blocks_[block].h = yy - blocks_[block].y + 2;

                            foreach (idx; 0 .. column)
                                if (idx < cells.length && cells[idx] != 0)
                                    blocks_[cells[idx]].h = blocks_[block].h;
                        }

                        cells = null;

                        yy = blocks_[block].y + blocks_[block].h - 4;
                        hh = 0;
                        block = addBlock(start, xx, yy, hsize_, 0);
                        row = block;
                        needspace = 0;
                        column = 0;
                        line = 0;

                        rc = getColor(getAttr(attrs, "BGCOLOR"), tc);
                    }
                    else if (buf.cmp("/TR") && row)
                    {
                        line = doAlign(block, line, xx, newalign, links);
                        blocks_[block].end = start;
                        blocks_[block].h += hh;
                        talign = Align.left;

                        xx = blocks_[row].x;
                        yy = blocks_[row].y + blocks_[row].h;

                        foreach (idx; row + 1 .. block + 1)
                            if ((blocks_[idx].y + blocks_[idx].h) > yy)
                                yy = blocks_[idx].y + blocks_[idx].h;

                        block = row;
                        blocks_[block].h = yy - blocks_[block].y + 2;

                        foreach (idx; 0 .. column)
                            if (idx < cells.length && cells[idx] != 0)
                                blocks_[cells[idx]].h = blocks_[block].h;

                        yy = blocks_[block].y + blocks_[block].h;
                        block = addBlock(start, xx, yy, hsize_, 0);
                        needspace = 0;
                        row = 0;
                        line = 0;
                    }
                    else if ((buf.cmp("TD") || buf.cmp("TH")) && row)
                    {
                        line = doAlign(block, line, xx, newalign, links);
                        blocks_[block].end = start;
                        blocks_[block].h += hh;

                        font = buf.cmp("TH") ? (textfont_ | bold) : textfont_;
                        fsize = textsize_;

                        xx = blocks_[row].x + fsize + 3 + tableOffset;
                        foreach (idx; 0 .. column)
                            if (idx < columns.length)
                                xx += columns[idx] + 6;

                        margins.push(xx - margins.current());

                        auto colspanAttr = getAttr(attrs, "COLSPAN");
                        int colspan = colspanAttr !is null ? atoiLike(colspanAttr) : 1;
                        if (colspan < 1)
                            colspan = 1;

                        ww = -6;
                        foreach (idx; 0 .. colspan)
                            if ((column + idx) < columns.length)
                                ww += columns[column + idx] + 6;

                        if (blocks_[block].end == blocks_[block].start && blocks_.length > 1)
                        {
                            blocks_ = blocks_[0 .. $ - 1];
                            block--;
                        }

                        pushfont(font, fsize);

                        yy = blocks_[row].y;
                        hh = 0;
                        block = addBlock(start, xx, yy, xx + ww, 0, border);
                        needspace = 0;
                        line = 0;
                        newalign = getAlign(attrs, toLower(buf[1]) == 'h' ? Align.center : Align.left);
                        talign = newalign;

                        while (cells.length <= column)
                            cells ~= 0;
                        cells[column] = cast(int) block;

                        column += colspan;

                        blocks_[block].bgcolor = getColor(getAttr(attrs, "BGCOLOR"), rc);
                    }
                    else if ((buf.cmp("/TD") || buf.cmp("/TH")) && row)
                    {
                        line = doAlign(block, line, xx, newalign, links);
                        popfont(font, fsize, fcolor);
                        xx = margins.pop();
                        talign = Align.left;
                    }
                    else if (buf.cmp("FONT"))
                    {
                        auto face = getAttr(attrs, "FACE");
                        if (face !is null)
                        {
                            if (startsWithCI(face, "helvetica") || startsWithCI(face, "arial")
                                || startsWithCI(face, "sans"))
                                font = helvetica;
                            else if (startsWithCI(face, "times") || startsWithCI(face, "serif"))
                                font = times;
                            else if (startsWithCI(face, "symbol"))
                                font = symbol;
                            else
                                font = courier;
                        }

                        auto sizeAttr = getAttr(attrs, "SIZE");
                        if (sizeAttr !is null)
                        {
                            if (sizeAttr.length > 0 && isDigit(sizeAttr[0]))
                                fsize = cast(int)(textsize_ * pow(1.2, atoiLike(sizeAttr) - 3.0));
                            else
                                fsize = cast(int)(fsize * pow(1.2, atoiLike(sizeAttr)));
                        }

                        pushfont(font, fsize);
                    }
                    else if (buf.cmp("/FONT"))
                        popfont(font, fsize, fcolor);
                    else if (buf.cmp("B") || buf.cmp("STRONG"))
                        pushfont(font |= bold, fsize);
                    else if (buf.cmp("I") || buf.cmp("EM"))
                        pushfont(font |= italic, fsize);
                    else if (buf.cmp("CODE") || buf.cmp("TT"))
                        pushfont(font = courier, fsize);
                    else if (buf.cmp("KBD"))
                        pushfont(font = courierBold, fsize);
                    else if (buf.cmp("VAR"))
                        pushfont(font = courierItalic, fsize);
                    else if (buf.cmp("/B") || buf.cmp("/STRONG") || buf.cmp("/I") || buf.cmp("/EM")
                        || buf.cmp("/CODE") || buf.cmp("/TT") || buf.cmp("/KBD") || buf.cmp("/VAR"))
                        popfont(font, fsize, fcolor);
                    else if (buf.cmp("IMG"))
                    {
                        int width = getLength(getAttr(attrs, "WIDTH"));
                        int height = getLength(getAttr(attrs, "HEIGHT"));

                        auto src = getAttr(attrs, "SRC");
                        if (src !is null)
                        {
                            auto img = getImage(src, width, height);
                            width = img.w();
                            height = img.h();
                        }

                        ww = width;

                        if (ww > hsize_)
                        {
                            hsize_ = ww;
                            done = false;
                            break;
                        }

                        if (needspace && xx > blocks_[block].x)
                            ww += cast(int) fl.draw.width(" ");

                        if ((xx + ww) > blocks_[block].w)
                        {
                            line = doAlign(block, line, xx, newalign, links);
                            xx = blocks_[block].x;
                            yy += hh;
                            blocks_[block].h += hh;
                            hh = 0;
                        }

                        if (linkdest.length)
                            addLink(linkdest, xx, yy - fsize, ww, height);

                        xx += ww;
                        if ((height + 2) > hh)
                            hh = height + 2;

                        needspace = 0;
                    }
                    buf.clear();
                }
                else if (i < value_.length && value_[i] == '\n' && pre)
                {
                    if (linkdest.length)
                        addLink(linkdest, xx, yy - hh, ww, hh);

                    if (xx > hsize_)
                    {
                        hsize_ = xx;
                        done = false;
                        break;
                    }

                    line = doAlign(block, line, xx, newalign, links);
                    xx = blocks_[block].x;
                    yy += hh;
                    blocks_[block].h += hh;
                    needspace = 0;
                    i++;
                }
                else if (i < value_.length && isWhite(value_[i]))
                {
                    needspace = 1;
                    if (pre)
                        xx += cast(int) width(" ");
                    i++;
                }
                else if (i < value_.length && value_[i] == '&')
                {
                    i++;

                    int qch = quoteChar(value_[i .. $]);

                    if (qch < 0)
                        buf ~= '&';
                    else
                    {
                        buf.add(cast(dchar) qch);
                        auto semi = value_[i .. $].indexOf(';');
                        i = i + semi + 1;
                    }

                    if ((fsize + 2) > hh)
                        hh = fsize + 2;
                }
                else if (i < value_.length)
                {
                    buf ~= value_[i];
                    i++;

                    if ((fsize + 2) > hh)
                        hh = fsize + 2;
                }
            }

            if (buf.size() > 0 && !head)
            {
                ww = cast(int) buf.width();

                if (ww > hsize_)
                {
                    hsize_ = ww;
                    done = false;
                }
                else
                {
                    if (needspace && xx > blocks_[block].x)
                        ww += cast(int) width(" ");

                    if ((xx + ww) > blocks_[block].w)
                    {
                        line = doAlign(block, line, xx, newalign, links);
                        xx = blocks_[block].x;
                        yy += hh;
                        blocks_[block].h += hh;
                        hh = 0;
                    }

                    if (linkdest.length)
                        addLink(linkdest, xx, yy - fsize, ww, fsize);

                    xx += ww;
                }
            }

            doAlign(block, line, xx, newalign, links);

            blocks_[block].end = i;
            size_ = yy + hh;

            // Make sure that the last block will have the correct height.
            if (hh > blocks_[block].h)
                blocks_[block].h = hh;
        }

        int dx = boxDw(b) - boxDx(b);
        int dy = boxDh(b) - boxDy(b);
        int ss = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
        int dw = boxDw(b) + ss;
        int dh = boxDh(b);

        if (hsize_ > (w() - dw))
        {
            hscrollbar_.show();

            dh += ss;

            if (size_ < (h() - dh))
            {
                scrollbar_.hide();
                hscrollbar_.resize(x() + boxDx(b), y() + h() - ss - dy, w() - boxDw(b), ss);
            }
            else
            {
                scrollbar_.show();
                scrollbar_.resize(x() + w() - ss - dx, y() + boxDy(b), ss, h() - ss - boxDh(b));
                hscrollbar_.resize(x() + boxDx(b), y() + h() - ss - dy, w() - ss - boxDw(b), ss);
            }
        }
        else
        {
            hscrollbar_.hide();

            if (size_ < (h() - dh))
                scrollbar_.hide();
            else
            {
                scrollbar_.resize(x() + w() - ss - dx, y() + boxDy(b), ss, h() - boxDh(b));
                scrollbar_.show();
            }
        }

        // Reset scrolling if it needs to be...
        if (scrollbar_.visible())
        {
            int temph = h() - boxDh(b);
            if (hscrollbar_.visible())
                temph -= ss;
            if ((topline_ + temph) > size_)
                topline(size_ - temph);
            else
                topline(topline_);
        }
        else
            topline(0);

        if (hscrollbar_.visible())
        {
            int tempw = w() - ss - boxDw(b);
            if ((leftline_ + tempw) > hsize_)
                leftline(hsize_ - tempw);
            else
                leftline(leftline_);
        }
        else
            leftline(0);
    }

    /**
     * Ported from `Fl_Help_View::Impl::format_table()`. Pre-scans a
     * `<TABLE>...</TABLE>` region (`tableStart` is the index of the
     * `<` of the opening `<TABLE>` tag itself) to compute a per-column
     * pixel width before `format()`'s real layout pass lays the table
     * out -- each `<TD>`'s X position depends on every earlier
     * column's width, but the widths themselves depend on every
     * cell's content, hence this separate measuring pre-pass.
     *
     * `columns`/the internal `minwidths` are growable D arrays, not
     * FLTK's fixed `int[MAX_COLUMNS]` (a 200-column cap) -- no
     * real document would approach that limit, and unlike a
     * stack-allocated C array a D array doesn't need a fixed bound at
     * all; this is the same "dissolve a C array's cap into a growable
     * D array" substitution already established elsewhere in this
     * port (e.g. `fl.preferences`'s child-node arrays replacing
     * FLTK's manual `realloc()` growth).
     *
     * One small, deliberate simplification: FLTK re-derives the
     * `<TABLE>` tag's own attribute string a second time at the very
     * end (`get_attr(table + 6, "WIDTH", ...)`, skipping past the
     * literal `"<TABLE"` by pointer arithmetic) purely because its own
     * scanning loop doesn't keep the first tag's `attrs` around after
     * moving past it. This port just captures `tableAttrs` when the
     * loop recognizes its own opening tag (`start == tableStart`)
     * instead -- same attribute string, no pointer-offset arithmetic
     * needed to re-find it.
     *
     * Shares `fstack_` (the font stack) with the enclosing `format()`
     * call -- every `pushfont()` here must be matched by a `popfont()`
     * before this function returns, or `format()`'s own subsequent
     * font tracking would be left corrupted. Relies on the table's
     * markup being well-formed (matched open/close tags), same
     * assumption FLTK makes.
     */
    private void formatTable(out int tableWidth, out int[] columns, size_t tableStart)
    {
        import std.ascii : isDigit, isWhite, toLower;
        import std.string : indexOf;

        int[] minwidths;
        void ensure(int col)
        {
            while (columns.length <= col)
            {
                columns ~= 0;
                minwidths ~= 0;
            }
        }

        int numColumns = 0;
        int colspan = 0;
        int maxWidth = 0;
        int pre = 0;
        int needspace = 0;

        Font font;
        Fontsize fsize;
        Color fcolor;
        fstack_.top(font, fsize, fcolor);

        EditBuffer buf;
        int column = -1;
        int width = 0;
        bool incell = false;
        string tableAttrs;
        size_t i = tableStart;

        void commitColumn()
        {
            if (column >= 0)
            {
                maxWidth /= colspan == 0 ? 1 : colspan;
                while (colspan > 0)
                {
                    ensure(column);
                    if (maxWidth > columns[column])
                        columns[column] = maxWidth;
                    column++;
                    colspan--;
                }
            }
        }

        while (i < value_.length)
        {
            char c = value_[i];

            if ((c == '<' || isWhite(c)) && buf.size() > 0 && incell)
            {
                if (needspace)
                {
                    buf ~= ' ';
                    needspace = 0;
                }

                int tempWidth = cast(int) buf.width();
                buf.clear();

                ensure(column);
                if (tempWidth > minwidths[column])
                    minwidths[column] = tempWidth;

                width += tempWidth;
                if (width > maxWidth)
                    maxWidth = width;
            }

            if (c == '<')
            {
                size_t start = i;
                i++;

                buf.clear();
                while (i < value_.length && value_[i] != '>' && !isWhite(value_[i]))
                {
                    buf ~= value_[i];
                    i++;
                }

                size_t attrsStart = i;
                while (i < value_.length && value_[i] != '>')
                    i++;
                string attrs = value_[attrsStart .. i];

                if (i < value_.length && value_[i] == '>')
                    i++;

                if (buf.cmp("BR") || buf.cmp("HR"))
                {
                    width = 0;
                    needspace = 0;
                }
                else if (buf.cmp("TABLE") && start == tableStart)
                {
                    // This function's own opening <TABLE> tag -- keep
                    // its attrs for the WIDTH lookup at the end, but
                    // otherwise fall through unmatched (matches
                    // FLTK: no branch there recognizes a bare
                    // "TABLE" at this exact position either).
                    tableAttrs = attrs;
                }
                else if (buf.cmp("TABLE") && start > tableStart)
                    break; // a nested table -- stop scanning this one
                else if (buf.cmp("CENTER") || buf.cmp("P")
                    || buf.cmp("H1") || buf.cmp("H2") || buf.cmp("H3")
                    || buf.cmp("H4") || buf.cmp("H5") || buf.cmp("H6")
                    || buf.cmp("UL") || buf.cmp("OL") || buf.cmp("DL")
                    || buf.cmp("LI") || buf.cmp("DD") || buf.cmp("DT")
                    || buf.cmp("PRE"))
                {
                    width = 0;
                    needspace = 0;

                    bool isHn = toLower(buf[0]) == 'h' && isDigit(buf[1]);
                    if (isHn)
                    {
                        font = helveticaBold;
                        fsize = textsize_ + '7' - buf[1];
                    }
                    else if (buf.cmp("DT"))
                    {
                        font = textfont_ | italic;
                        fsize = textsize_;
                    }
                    else if (buf.cmp("PRE"))
                    {
                        font = courier;
                        fsize = textsize_;
                        pre = 1;
                    }
                    else if (buf.cmp("LI"))
                    {
                        width += 4 * fsize;
                        font = textfont_;
                        fsize = textsize_;
                    }
                    else
                    {
                        font = textfont_;
                        fsize = textsize_;
                    }

                    pushfont(font, fsize);
                }
                else if (buf.cmp("/CENTER") || buf.cmp("/P")
                    || buf.cmp("/H1") || buf.cmp("/H2") || buf.cmp("/H3")
                    || buf.cmp("/H4") || buf.cmp("/H5") || buf.cmp("/H6")
                    || buf.cmp("/PRE") || buf.cmp("/UL") || buf.cmp("/OL") || buf.cmp("/DL"))
                {
                    width = 0;
                    needspace = 0;
                    popfont(font, fsize, fcolor);
                }
                else if (buf.cmp("TR") || buf.cmp("/TR") || buf.cmp("/TABLE"))
                {
                    commitColumn();

                    if (buf.cmp("/TABLE"))
                        break;

                    needspace = 0;
                    column = -1;
                    width = 0;
                    maxWidth = 0;
                    incell = false;
                }
                else if (buf.cmp("TD") || buf.cmp("TH"))
                {
                    commitColumn();
                    if (column < 0)
                        column = 0;

                    auto colspanAttr = getAttr(attrs, "COLSPAN");
                    colspan = colspanAttr !is null ? atoiLike(colspanAttr) : 1;
                    if (colspan < 1)
                        colspan = 1;

                    if ((column + colspan) >= numColumns)
                        numColumns = column + colspan;

                    needspace = 0;
                    width = 0;
                    incell = true;

                    font = buf.cmp("TH") ? (textfont_ | bold) : textfont_;
                    fsize = textsize_;
                    pushfont(font, fsize);

                    auto widthAttr = getAttr(attrs, "WIDTH");
                    maxWidth = widthAttr !is null ? getLength(widthAttr) : 0;
                }
                else if (buf.cmp("/TD") || buf.cmp("/TH"))
                {
                    incell = false;
                    popfont(font, fsize, fcolor);
                }
                else if (buf.cmp("B") || buf.cmp("STRONG"))
                    pushfont(font |= bold, fsize);
                else if (buf.cmp("I") || buf.cmp("EM"))
                    pushfont(font |= italic, fsize);
                else if (buf.cmp("CODE") || buf.cmp("TT"))
                    pushfont(font = courier, fsize);
                else if (buf.cmp("KBD"))
                    pushfont(font = courierBold, fsize);
                else if (buf.cmp("VAR"))
                    pushfont(font = courierItalic, fsize);
                else if (buf.cmp("/B") || buf.cmp("/STRONG") || buf.cmp("/I") || buf.cmp("/EM")
                    || buf.cmp("/CODE") || buf.cmp("/TT") || buf.cmp("/KBD") || buf.cmp("/VAR"))
                    popfont(font, fsize, fcolor);
                else if (buf.cmp("IMG") && incell)
                {
                    int iwidth = getLength(getAttr(attrs, "WIDTH"));
                    int iheight = getLength(getAttr(attrs, "HEIGHT"));
                    auto src = getAttr(attrs, "SRC");
                    if (src !is null)
                    {
                        auto img = getImage(src, iwidth, iheight);
                        iwidth = img.w();
                        iheight = img.h();
                    }
                    ensure(column < 0 ? 0 : column);
                    int mwIdx = column < 0 ? 0 : column;
                    if (iwidth > minwidths[mwIdx])
                        minwidths[mwIdx] = iwidth;
                    width += iwidth;
                    if (needspace)
                        width += cast(int) fl.draw.width(" ");
                    if (width > maxWidth)
                        maxWidth = width;
                    needspace = 0;
                }
                buf.clear();
            }
            else if (c == '\n' && pre)
            {
                width = 0;
                needspace = 0;
                i++;
            }
            else if (isWhite(c))
            {
                needspace = 1;
                i++;
            }
            else if (c == '&')
            {
                i++;
                int qch = quoteChar(value_[i .. $]);
                if (qch < 0)
                    buf ~= '&';
                else
                {
                    buf.add(cast(dchar) qch);
                    auto semi = value_[i .. $].indexOf(';');
                    i = i + semi + 1;
                }
            }
            else
            {
                buf ~= c;
                i++;
            }
        }

        tableWidth = (tableAttrs !is null && getAttr(tableAttrs, "WIDTH") !is null)
            ? getLength(getAttr(tableAttrs, "WIDTH")) : 0;

        if (numColumns == 0)
            return;

        ensure(numColumns - 1);

        int totalWidth = 0;
        foreach (col; 0 .. numColumns)
            totalWidth += columns[col];

        int scaleWidth = tableWidth;
        int scrollsize = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
        if (scaleWidth == 0)
            scaleWidth = totalWidth > (hsize_ - scrollsize) ? (hsize_ - scrollsize) : totalWidth;

        if (totalWidth < scaleWidth)
        {
            tableWidth = 0;
            scaleWidth = (scaleWidth - totalWidth) / numColumns;
            foreach (col; 0 .. numColumns)
            {
                columns[col] += scaleWidth;
                tableWidth += columns[col];
            }
        }
        else if (totalWidth > scaleWidth)
        {
            foreach (col; 0 .. numColumns)
            {
                totalWidth -= minwidths[col];
                scaleWidth -= minwidths[col];
            }
            if (totalWidth > 0)
            {
                foreach (col; 0 .. numColumns)
                {
                    columns[col] -= minwidths[col];
                    columns[col] = scaleWidth * columns[col] / totalWidth;
                    columns[col] += minwidths[col];
                }
            }
            tableWidth = 0;
            foreach (col; 0 .. numColumns)
                tableWidth += columns[col];
        }
        else if (tableWidth == 0)
            tableWidth = totalWidth;

        columns = columns[0 .. numColumns];
    }

    /// Ported from `Fl_Help_View::Impl::hv_draw()`. `t` is one already
    /// laid-out run of text (a "word", matching `EditBuffer buf`'s
    /// contents at each flush point in `draw()`'s own char walk), not
    /// the whole document. In `Mode.draw`, actually paints (with a
    /// selection-highlight rectangle if `currentPos_` falls inside
    /// `[selectionFirst_, selectionLast_)`); in `Mode.push`/`drag`, it
    /// paints nothing at all and instead checks whether the mouse
    /// event position falls within this text's bounding box, updating
    /// the module-level `selectionPush*_`/`selectionDrag*_` offsets --
    /// see this module's top comment for why callers reach this
    /// branch via a real `draw()` call under a degenerate `pushClip()`
    /// rather than FLTK's offscreen buffer.
    private void hvDraw(string t, int x, int y, int entityExtraLength = 0)
    {
        if (drawMode_ == Mode.draw)
        {
            if (selected_ && currentPos_ < selectionLast_ && currentPos_ >= selectionFirst_)
            {
                Color c = fl_color();
                fl_color(tmpSelectionColor_);
                int tw = cast(int) width(t);
                if (currentPos_ + cast(int) t.length < selectionLast_)
                    tw += cast(int) width(" ");
                fl_rectf(x, y + descent() - height(), tw, height());
                fl_color(selectionTextColor_);
                fl_draw(t, cast(int) t.length, x, y);
                fl_color(c);
            }
            else
                fl_draw(t, cast(int) t.length, x, y);
        }
        else
        {
            int tw = cast(int) width(t);
            if (fl.core.eventX() >= x && fl.core.eventX() < x + tw)
            {
                if (fl.core.eventY() >= y - height() + descent()
                    && fl.core.eventY() <= y + descent())
                {
                    int f = currentPos_;
                    int l = f + cast(int) t.length;
                    if (drawMode_ == Mode.push)
                    {
                        selectionPushFirst_ = selectionDragFirst_ = f;
                        selectionPushLast_ = selectionDragLast_ = l;
                    }
                    else
                    {
                        selectionDragFirst_ = f;
                        selectionDragLast_ = l + entityExtraLength;
                    }
                }
            }
        }
    }

    /// Ported from `Fl_Help_View::Impl::begin_selection()`.
    private bool beginSelection()
    {
        clearSelection();
        selectionPushFirst_ = selectionPushLast_ = 0;
        selectionDragFirst_ = selectionDragLast_ = 0;

        drawMode_ = Mode.push;
        // See this module's top comment: a degenerate pushClip()
        // substitutes for FLTK's offscreen-buffer wrapper around
        // this same real draw() call.
        pushClip(0, 0, 0, 0);
        draw();
        popClip();
        drawMode_ = Mode.draw;

        return selectionPushLast_ != 0;
    }

    /// Ported from `Fl_Help_View::Impl::extend_selection()`.
    private bool extendSelection()
    {
        if (fl.core.eventIsClick())
            return false;

        if (fl.core.focus() !is this)
            fl.core.focus(this);

        int sf = selectionFirst_, sl = selectionLast_;

        selected_ = true;

        drawMode_ = Mode.drag;
        pushClip(0, 0, 0, 0);
        draw();
        popClip();
        drawMode_ = Mode.draw;

        selectionFirst_ = selectionPushFirst_ < selectionDragFirst_ ? selectionPushFirst_ : selectionDragFirst_;
        selectionLast_ = selectionPushLast_ > selectionDragLast_ ? selectionPushLast_ : selectionDragLast_;

        return sf != selectionFirst_ || sl != selectionLast_;
    }

    /// Ported from `Fl_Help_View::Impl::end_selection()`.
    private void endSelection()
    {
        selectionPushFirst_ = 0;
        selectionPushLast_ = 0;
        selectionDragFirst_ = 0;
        selectionDragLast_ = 0;
    }

    /// Ported from `Fl_Help_View::Impl::follow_link()`.
    private void followLink(Link linkp)
    {
        clearSelection();
        setChanged();
        string target = linkp.target;

        if (linkp.filename_ != filename_ && linkp.filename_.length > 0)
        {
            string url;
            auto directoryScheme = urlScheme(directory_);
            auto filenameScheme = urlScheme(linkp.filename_);
            if (directoryScheme > 0 && filenameScheme == 0)
            {
                if (linkp.filename_[0] == '/')
                    url = directory_[0 .. directoryScheme] ~ linkp.filename_;
                else
                    url = directory_ ~ "/" ~ linkp.filename_;
            }
            else if (linkp.filename_[0] != '/' && filenameScheme == 0)
            {
                if (directory_.length > 0)
                    url = directory_ ~ "/" ~ linkp.filename_;
                else
                {
                    import std.file : getcwd;

                    url = "file:" ~ getcwd() ~ "/" ~ linkp.filename_;
                }
            }
            else
                url = linkp.filename_;

            if (linkp.target.length > 0)
                url ~= "#" ~ linkp.target;

            load(url);
        }
        else if (target.length > 0)
            topline(target);
        else
            topline(0);

        leftline(0);
    }

    /**
     * Ported from `Fl_Help_View::Impl::draw()`. TD/TH cell-background/
     * border drawing is real (Milestone 2) -- see the `buf.cmp("TD")
     * || buf.cmp("TH")` branch below. `<IMG>` draws real pixels too
     * now -- see the module's own top comment.
     */
    override void draw()
    {
        import fl.enumerations : Boxtype, gray;
        import std.ascii : isWhite, toLower, isDigit;
        import std.string : indexOf;
        import std.math : pow;
        import std.format : format;

        Boxtype b = box() ? box() : Boxtype.downBox;

        int ww = w();
        int hh = h();

        drawBox(b, x(), y(), ww, hh, bgcolor_);

        if (hscrollbar_.visible() || scrollbar_.visible())
        {
            int scrollsize = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
            bool horVis = hscrollbar_.visible();
            bool verVis = scrollbar_.visible();
            int scornX = x() + ww - (verVis ? scrollsize : 0) - boxDw(b) + boxDx(b);
            int scornY = y() + hh - (horVis ? scrollsize : 0) - boxDh(b) + boxDy(b);
            if (horVis)
            {
                // Guarded on drawMode_ -- unlike the rest of this
                // function, resize()/initSizes() are real state
                // mutations, not suppressible by the degenerate
                // pushClip(0,0,0,0) this module's top comment
                // describes for the Mode.push/drag measurement passes
                // (that only suppresses *pixel output*). Without this
                // guard, beginSelection()/extendSelection() calling
                // this same draw() on every click/drag tick would
                // mutate scrollbar geometry and reset the group's
                // resize baseline as a side effect of merely measuring
                // a mouse position -- FLTK never had this exposure
                // since none of its own callers reach this code from a
                // live per-drag path the way this port's selection
                // mechanism does.
                if (drawMode_ == Mode.draw && hscrollbar_.h() != scrollsize)
                {
                    hscrollbar_.resize(x(), scornY, scornX - x(), scrollsize);
                    initSizes();
                }
                drawChild(hscrollbar_);
                hh -= scrollsize;
            }
            if (verVis)
            {
                if (drawMode_ == Mode.draw && scrollbar_.w() != scrollsize)
                {
                    scrollbar_.resize(scornX, y(), scrollsize, scornY - y());
                    initSizes();
                }
                drawChild(scrollbar_);
                ww -= scrollsize;
            }
            if (horVis && verVis)
            {
                fl_color(gray);
                fl_rectf(scornX, scornY, scrollsize, scrollsize);
            }
        }

        if (value_ is null)
            return;

        if (selected_)
        {
            if (fl.core.focus() is this)
                tmpSelectionColor_ = selectionColor();
            else
                tmpSelectionColor_ = colorAverage(bgcolor_, selectionColor(), 0.8f);
            selectionTextColor_ = contrast(textcolor_, tmpSelectionColor_);
        }
        currentPos_ = 0;

        pushClip(x() + boxDx(b), y() + boxDy(b), ww - boxDw(b), hh - boxDh(b));
        scope (exit)
            popClip();
        fl_color(textcolor_);

        foreach (ref const blk; blocks_)
        {
            if ((blk.y + blk.h) < topline_ || blk.y >= (topline_ + h()))
                continue;

            int line = 0;
            int xx = blk.line[line];
            int yy = blk.y - topline_;
            hh = 0;
            int pre = 0;
            int head = 0;
            int needspace = 0;
            int underline = 0;

            Font font;
            Fontsize fsize;
            Color fcolor;
            initfont(font, fsize, fcolor);
            int entityExtraLength = 0;

            EditBuffer buf;
            size_t i = blk.start;

            while (i < blk.end)
            {
                char c = value_[i];

                if ((c == '<' || isWhite(c)) && buf.size() > 0)
                {
                    if (!head && !pre)
                    {
                        ww = cast(int) buf.width();

                        if (needspace && xx > blk.x)
                            xx += cast(int) width(" ");

                        if ((xx + ww) > blk.w)
                        {
                            if (line < 31)
                                line++;
                            xx = blk.line[line];
                            yy += hh;
                            hh = 0;
                        }

                        hvDraw(buf.str(), xx + x() - leftline_, yy + y(), entityExtraLength);
                        buf.clear();
                        entityExtraLength = 0;
                        if (underline)
                        {
                            int xtraWw = isWhite(value_[i]) ? cast(int) width(" ") : 0;
                            fl_xyline(xx + x() - leftline_, yy + y() + 1,
                                xx + x() - leftline_ + ww + xtraWw);
                        }
                        currentPos_ = cast(int) i;

                        xx += ww;
                        if ((fsize + 2) > hh)
                            hh = fsize + 2;

                        needspace = 0;
                    }
                    else if (pre)
                    {
                        while (i < blk.end && isWhite(value_[i]))
                        {
                            if (value_[i] == '\n')
                            {
                                hvDraw(buf.str(), xx + x() - leftline_, yy + y());
                                if (underline)
                                    fl_xyline(xx + x() - leftline_, yy + y() + 1,
                                        xx + x() - leftline_ + cast(int) buf.width());
                                buf.clear();
                                currentPos_ = cast(int) i;
                                if (line < 31)
                                    line++;
                                xx = blk.line[line];
                                yy += hh;
                                hh = fsize + 2;
                            }
                            else if (value_[i] == '\t')
                            {
                                buf ~= ' ';
                                while (buf.size() & 7)
                                    buf ~= ' ';
                            }
                            else
                                buf ~= ' ';

                            if ((fsize + 2) > hh)
                                hh = fsize + 2;
                            i++;
                        }

                        if (buf.size() > 0)
                        {
                            hvDraw(buf.str(), xx + x() - leftline_, yy + y());
                            ww = cast(int) buf.width();
                            buf.clear();
                            if (underline)
                                fl_xyline(xx + x() - leftline_, yy + y() + 1, xx + x() - leftline_ + ww);
                            xx += ww;
                            currentPos_ = cast(int) i;
                        }

                        needspace = 0;
                    }
                    else
                    {
                        buf.clear();
                        while (i < blk.end && isWhite(value_[i]))
                            i++;
                        currentPos_ = cast(int) i;
                    }
                }

                if (i < blk.end && value_[i] == '<')
                {
                    i++;

                    if (i + 3 <= value_.length && value_[i .. i + 3] == "!--")
                    {
                        i += 3;
                        auto closePos = value_[i .. $].indexOf("-->");
                        if (closePos >= 0)
                        {
                            i = i + closePos + 3;
                            continue;
                        }
                        else
                            break;
                    }

                    while (i < blk.end && value_[i] != '>' && !isWhite(value_[i]))
                    {
                        buf ~= value_[i];
                        i++;
                    }

                    size_t attrsStart = i;
                    while (i < blk.end && value_[i] != '>')
                        i++;
                    string attrs = value_[attrsStart .. i];

                    if (i < blk.end && value_[i] == '>')
                        i++;

                    currentPos_ = cast(int) i;

                    if (buf.cmp("HEAD"))
                        head = 1;
                    else if (buf.cmp("BR"))
                    {
                        if (line < 31)
                            line++;
                        xx = blk.line[line];
                        yy += hh;
                        hh = 0;
                    }
                    else if (buf.cmp("HR"))
                    {
                        fl_line(blk.x + x(), yy + y(), blk.w + x(), yy + y());
                        if (line < 31)
                            line++;
                        xx = blk.line[line];
                        yy += 2 * fsize;
                        hh = 0;
                    }
                    else if (buf.cmp("CENTER") || buf.cmp("P")
                        || buf.cmp("H1") || buf.cmp("H2") || buf.cmp("H3")
                        || buf.cmp("H4") || buf.cmp("H5") || buf.cmp("H6")
                        || buf.cmp("UL") || buf.cmp("OL") || buf.cmp("DL")
                        || buf.cmp("LI") || buf.cmp("DD") || buf.cmp("DT")
                        || buf.cmp("PRE"))
                    {
                        if (toLower(buf[0]) == 'h')
                        {
                            font = helveticaBold;
                            fsize = textsize_ + '7' - buf[1];
                        }
                        else if (buf.cmp("DT"))
                        {
                            font = textfont_ | italic;
                            fsize = textsize_;
                        }
                        else if (buf.cmp("PRE"))
                        {
                            font = courier;
                            fsize = textsize_;
                            pre = 1;
                        }

                        if (buf.cmp("LI"))
                        {
                            if (blk.ol)
                            {
                                string label = format("%d. ", blk.olNum);
                                hvDraw(label, xx - cast(int) width(label) + x() - leftline_, yy + y());
                            }
                            else
                                hvDraw("•", xx - fsize + x() - leftline_, yy + y());
                        }

                        pushfont(font, fsize);
                        buf.clear();
                    }
                    else if (buf.cmp("A") && getAttr(attrs, "HREF") !is null)
                    {
                        fl_color(linkcolor_);
                        underline = 1;
                    }
                    else if (buf.cmp("/A"))
                    {
                        fl_color(textcolor_);
                        underline = 0;
                    }
                    else if (buf.cmp("TD") || buf.cmp("TH"))
                    {
                        if (toLower(buf[1]) == 'h')
                            pushfont(font |= bold, fsize);
                        else
                            pushfont(font = textfont_, fsize);

                        int tx = blk.x - 4 - leftline_;
                        int ty = blk.y - topline_ - fsize - 3;
                        int tw = blk.w - blk.x + 7;
                        int th = blk.h + fsize - 5;

                        if (tx < 0)
                        {
                            tw += tx;
                            tx = 0;
                        }
                        if (ty < 0)
                        {
                            th += ty;
                            ty = 0;
                        }

                        tx += x();
                        ty += y();

                        if (blk.bgcolor != bgcolor_)
                        {
                            fl_color(blk.bgcolor);
                            fl_rectf(tx, ty, tw, th);
                            fl_color(textcolor_);
                        }

                        if (blk.border)
                            fl_rect(tx, ty, tw, th);
                    }
                    else if (buf.cmp("FONT"))
                    {
                        auto colorAttr = getAttr(attrs, "COLOR");
                        if (colorAttr !is null)
                            textcolor_ = getColor(colorAttr, textcolor_);

                        auto face = getAttr(attrs, "FACE");
                        if (face !is null)
                        {
                            if (startsWithCI(face, "helvetica") || startsWithCI(face, "arial")
                                || startsWithCI(face, "sans"))
                                font = helvetica;
                            else if (startsWithCI(face, "times") || startsWithCI(face, "serif"))
                                font = times;
                            else if (startsWithCI(face, "symbol"))
                                font = symbol;
                            else
                                font = courier;
                        }

                        auto sizeAttr = getAttr(attrs, "SIZE");
                        if (sizeAttr !is null)
                        {
                            // FLTK uses atof() here vs. atoi() in
                            // format()'s otherwise-identical FONT SIZE
                            // handling -- a real inconsistency between
                            // the two, harmless for integer SIZE
                            // values (the only kind real documents
                            // use); atoiLike() is reused for both.
                            if (sizeAttr.length > 0 && isDigit(sizeAttr[0]))
                                fsize = cast(int)(textsize_ * pow(1.2, atoiLike(sizeAttr) - 3.0));
                            else
                                fsize = cast(int)(fsize * pow(1.2, atoiLike(sizeAttr) - 3.0));
                        }

                        pushfont(font, fsize);
                    }
                    else if (buf.cmp("/FONT"))
                        popfont(font, fsize, textcolor_);
                    else if (buf.cmp("U"))
                        underline = 1;
                    else if (buf.cmp("/U"))
                        underline = 0;
                    else if (buf.cmp("B") || buf.cmp("STRONG"))
                        pushfont(font |= bold, fsize);
                    else if (buf.cmp("I") || buf.cmp("EM"))
                        pushfont(font |= italic, fsize);
                    else if (buf.cmp("CODE") || buf.cmp("TT"))
                        pushfont(font = courier, fsize);
                    else if (buf.cmp("KBD"))
                        pushfont(font = courierBold, fsize);
                    else if (buf.cmp("VAR"))
                        pushfont(font = courierItalic, fsize);
                    else if (buf.cmp("/HEAD"))
                        head = 0;
                    else if (buf.cmp("/H1") || buf.cmp("/H2") || buf.cmp("/H3")
                        || buf.cmp("/H4") || buf.cmp("/H5") || buf.cmp("/H6")
                        || buf.cmp("/B") || buf.cmp("/STRONG") || buf.cmp("/I") || buf.cmp("/EM")
                        || buf.cmp("/CODE") || buf.cmp("/TT") || buf.cmp("/KBD") || buf.cmp("/VAR"))
                        popfont(font, fsize, fcolor);
                    else if (buf.cmp("/PRE"))
                    {
                        popfont(font, fsize, fcolor);
                        pre = 0;
                    }
                    else if (buf.cmp("IMG"))
                    {
                        int width = getLength(getAttr(attrs, "WIDTH"));
                        int height = getLength(getAttr(attrs, "HEIGHT"));

                        Image img;
                        auto src = getAttr(attrs, "SRC");
                        if (src !is null)
                        {
                            img = getImage(src, width, height);
                            // Only fills in a *missing* dimension here
                            // (vs. format()'s unconditional overwrite
                            // for the same tag) -- a real FLTK
                            // inconsistency, ported faithfully; see
                            // FLTK_ISSUES.md.
                            if (width == 0)
                                width = img.w();
                            if (height == 0)
                                height = img.h();
                        }

                        ww = width;

                        if (needspace && xx > blk.x)
                            xx += cast(int) fl.draw.width(" ");

                        if ((xx + ww) > blk.w)
                        {
                            if (line < 31)
                                line++;
                            xx = blk.line[line];
                            yy += hh;
                            hh = 0;
                        }

                        if (img !is null)
                            img.draw(xx + x() - leftline_,
                                yy + y() - fl.draw.height() + descent() + 2);

                        xx += ww;
                        if ((height + 2) > hh)
                            hh = height + 2;

                        needspace = 0;
                    }
                    buf.clear();
                }
                else if (i < blk.end && value_[i] == '\n' && pre)
                {
                    hvDraw(buf.str(), xx + x() - leftline_, yy + y());
                    buf.clear();

                    if (line < 31)
                        line++;
                    xx = blk.line[line];
                    yy += hh;
                    hh = fsize + 2;
                    needspace = 0;

                    i++;
                    currentPos_ = cast(int) i;
                }
                else if (i < blk.end && isWhite(value_[i]))
                {
                    if (pre)
                    {
                        if (value_[i] == ' ')
                            buf ~= ' ';
                        else
                        {
                            buf ~= ' ';
                            while (buf.size() & 7)
                                buf ~= ' ';
                        }
                    }

                    i++;
                    if (!pre)
                        currentPos_ = cast(int) i;
                    needspace = 1;
                }
                else if (i < blk.end && value_[i] == '&')
                {
                    i++;

                    int qch = quoteChar(value_[i .. $]);

                    if (qch < 0)
                        buf ~= '&';
                    else
                    {
                        size_t utf8l = buf.size();
                        buf.add(cast(dchar) qch);
                        utf8l = buf.size() - utf8l;
                        auto semi = value_[i .. $].indexOf(';');
                        size_t newI = i + semi + 1;
                        entityExtraLength += cast(int)(newI - (i - 1)) - cast(int) utf8l;
                        i = newI;
                    }

                    if ((fsize + 2) > hh)
                        hh = fsize + 2;
                }
                else if (i < blk.end)
                {
                    buf ~= value_[i];
                    i++;
                    if ((fsize + 2) > hh)
                        hh = fsize + 2;
                }
            }

            int wwFinal = 0;
            if (buf.size() > 0 && !pre && !head)
            {
                wwFinal = cast(int) buf.width();

                if (needspace && xx > blk.x)
                    xx += cast(int) width(" ");

                if ((xx + wwFinal) > blk.w)
                {
                    if (line < 31)
                        line++;
                    xx = blk.line[line];
                    yy += hh;
                    hh = 0;
                }
            }

            if (buf.size() > 0 && !head)
            {
                hvDraw(buf.str(), xx + x() - leftline_, yy + y());
                if (underline)
                    fl_xyline(xx + x() - leftline_, yy + y() + 1, xx + x() - leftline_ + wwFinal);
                currentPos_ = cast(int) i;
            }
        }
    }

    /// Ported from `Fl_Help_View::Impl::handle()`.
    override int handle(Event event)
    {
        import fl.enumerations : Cursor, rightMouse, stateMeta, stateAlt,
            stateShift, stateCtrl, stateCommand;

        static Link linkp; // currently clicked link -- genuinely
        // process-wide FLTK too (its own `static` local), see the
        // `selectionPush*_` fields' own note on this pattern.

        int xx = fl.core.eventX() - x() + leftline_;
        int yy = fl.core.eventY() - y() + topline_;

        switch (event)
        {
        case Event.focus:
            if (selected_)
                redraw();
            return 1;
        case Event.unfocus:
            if (selected_)
                redraw();
            return 1;
        case Event.enter:
            super.handle(event);
            return 1;
        case Event.leave:
            if (window() !is null)
                window().cursor(Cursor.default_);
            break;
        case Event.move:
            if (window() !is null)
                window().cursor(findLink(xx, yy) !is null ? Cursor.hand : Cursor.default_);
            return 1;
        case Event.push:
            if (fl.core.eventButton() == rightMouse)
            {
                MenuItem[2] items;
                items[0] = MenuItem(copyMenuText);
                if (!textSelected())
                    items[0].deactivate();
                if (window() !is null)
                    window().cursor(Cursor.default_);

                // Deliberate departure from FLTK (`rmb_menu->
                // popup(Fl::event_x(), Fl::event_y())`), matching
                // fl.input.d's own precedent for the same RMB copy
                // menu: ask the server for the real current mouse
                // position instead of computing one from Fl::event_x()
                // and window offsets, which is fragile for any widget
                // whose own coordinates aren't simply parent-relative
                // in the usual way.
                int screenX, screenY;
                fl.core.getMouse(screenX, screenY);
                auto picked = fl.menu_popup.popup(&items[0], screenX, screenY);
                if (picked !is null)
                    copy();
                return 1;
            }

            if (super.handle(event))
                return 1;

            linkp = findLink(xx, yy);
            if (linkp !is null)
            {
                if (window() !is null)
                    window().cursor(Cursor.hand);
                return 1;
            }

            if (beginSelection())
            {
                selectionMode_ = Mode.push;
                if (window() !is null)
                    window().cursor(Cursor.insert);
                return 1;
            }

            if (window() !is null)
                window().cursor(Cursor.default_);
            return 1;
        case Event.drag:
            if (linkp !is null)
            {
                if (fl.core.eventIsClick())
                {
                    if (window() !is null)
                        window().cursor(Cursor.hand);
                }
                else
                {
                    linkp = null;
                    if (beginSelection())
                    {
                        selectionMode_ = Mode.push;
                        if (window() !is null)
                            window().cursor(Cursor.insert);
                    }
                }
            }

            if (selectionMode_ == Mode.push)
            {
                if (extendSelection())
                    redraw();
                if (window() !is null)
                    window().cursor(Cursor.insert);
                return 1;
            }

            if (window() !is null)
                window().cursor(Cursor.default_);
            return 1;
        case Event.release:
            if (linkp !is null)
            {
                if (fl.core.eventIsClick())
                    followLink(linkp);
                if (window() !is null)
                    window().cursor(Cursor.default_);
                linkp = null;
                return 1;
            }

            if (selectionMode_ == Mode.push)
            {
                endSelection();
                selectionMode_ = Mode.draw;
                return 1;
            }
            return 1;
        case Event.shortcut:
            {
                auto mods = fl.core.eventState() & (stateMeta | stateAlt | stateShift | stateCtrl);
                if (mods == stateCommand)
                {
                    switch (fl.core.eventKey())
                    {
                    case 'a':
                        selectAll();
                        redraw();
                        return 1;
                    case 'c':
                    case 'x':
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

    // ---- Widget management ----

    override void resize(int xx, int yy, int ww, int hh)
    {
        import fl.enumerations : Boxtype;

        Boxtype b = box() ? box() : Boxtype.downBox;

        super.resize(xx, yy, ww, hh);

        int scrollsize = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
        scrollbar_.resize(x() + w() - scrollsize - boxDw(b) + boxDx(b),
            y() + boxDy(b), scrollsize, h() - scrollsize - boxDh(b));
        hscrollbar_.resize(x() + boxDx(b),
            y() + h() - scrollsize - boxDh(b) + boxDy(b),
            w() - scrollsize - boxDw(b), scrollsize);
        format();
    }

    // ---- HTML source and raw data ----

    /// Sets the current help text buffer and reformats. `null` clears
    /// the widget, matching FLTK's `nullptr` contract.
    void value(string val)
    {
        clearSelection();
        freeData();
        setChanged();

        if (val is null)
            return;

        value_ = val;
        initialLoad_ = true;
        format();
        initialLoad_ = false;

        topline(0);
        leftline(0);
    }

    string value() const => value_;

    /**
     * Ported from `Fl_Help_View::Impl::load()`. Non-`file:` schemes
     * (ftp/http/https/ipp/mailto/news) dispatch through
     * `fl.filename.openUri()` (see this module's top comment): on
     * success this returns 0 and leaves the view's content unchanged (an external
     * handler took over); on failure, a real in-view HTML error page
     * is built and displayed, matching FLTK exactly.
     */
    int load(string f)
    {
        import std.string : indexOf, lastIndexOf, startsWith;
        import std.file : read, getcwd;

        if (f.startsWith("ftp:") || f.startsWith("http:") || f.startsWith("https:")
            || f.startsWith("ipp:") || f.startsWith("mailto:") || f.startsWith("news:"))
        {
            string urimsg;
            if (!openUri(f, urimsg))
            {
                clearSelection();

                string newname = f;
                auto hashPos = newname.indexOf('#');
                if (hashPos >= 0)
                    newname = newname[0 .. hashPos];

                if (linkFunc_ !is null)
                {
                    auto n = linkFunc_(this, newname);
                    if (n is null)
                        return 0;
                }

                freeData();

                filename_ = newname;
                directory_ = newname;
                auto slashPos = directory_.lastIndexOf('/');
                if (slashPos < 0)
                    directory_ = "";
                else if (slashPos > 0 && directory_[slashPos - 1] != '/')
                    directory_ = directory_[0 .. slashPos];

                value_ = "<HTML><HEAD><TITLE>Error</TITLE></HEAD>"
                    ~ "<BODY><H1>Error</H1>"
                    ~ "<P>Unable to follow the link \"" ~ f ~ "\" - " ~ urimsg ~ ".</P></BODY>";
                initialLoad_ = true;
                format();
                initialLoad_ = false;
                return -1;
            }
            else
                return 0;
        }

        clearSelection();

        string newname = f;
        string target;
        auto hashPos = newname.indexOf('#');
        if (hashPos >= 0)
        {
            target = newname[hashPos + 1 .. $];
            newname = newname[0 .. hashPos];
        }

        string localname = newname;
        if (linkFunc_ !is null)
        {
            auto n = linkFunc_(this, newname);
            if (n is null)
                return -1;
            localname = n;
        }

        freeData();

        filename_ = newname;
        directory_ = newname;
        auto slashPos = directory_.lastIndexOf('/');
        if (slashPos < 0)
            directory_ = "";
        else if (slashPos > 0 && directory_[slashPos - 1] != '/')
            directory_ = directory_[0 .. slashPos];

        if (localname.startsWith("file:"))
            localname = localname[5 .. $];

        int ret = 0;
        try
        {
            value_ = cast(string) read(localname);
        }
        catch (Exception e)
        {
            value_ = "<HTML><HEAD><TITLE>Error</TITLE></HEAD>"
                ~ "<BODY><H1>Error</H1>"
                ~ "<P>Unable to follow the link \"" ~ localname ~ "\" - " ~ e.msg ~ ".</P></BODY>";
            ret = -1;
        }

        initialLoad_ = true;
        format();
        initialLoad_ = false;

        if (target.length > 0)
            topline(target);
        else
            topline(0);

        return ret;
    }

    /**
     * Ported from `Fl_Help_View::Impl::find()`. See FLTK's own
     * doc comment (transcribed on the D declaration below) for the
     * matching rules: HTML tags never match, entities decode to
     * Unicode first, ASCII letters compare case-insensitively,
     * newlines count as a single space, everything else compares
     * byte-for-byte.
     *
     * *FIXME* *UTF-8* (ported from FLTK's own flagged comment,
     * not resolved here): when a decoded HTML entity's code point is
     * outside ASCII, the comparison below decodes one code point from
     * the search string and compares code-point values -- correct as
     * far as it goes, but a search string containing a *pre-composed*
     * multi-codepoint sequence that's canonically equivalent to the
     * entity (e.g. combining diacritics) will never match. Same
     * limitation FLTK, ported faithfully rather than silently
     * fixed.
     */
    int find(string s, int p = 0)
    {
        import std.string : indexOf;
        import std.utf : decode;
        import std.ascii : toLower;

        if (s is null || value_ is null)
            return -1;

        if (p < 0 || p >= cast(int) value_.length)
            p = 0;

        foreach (ref const blk; blocks_)
        {
            if (blk.end < cast(size_t) p)
                continue;

            size_t bp = blk.start < cast(size_t) p ? cast(size_t) p : blk.start;

            bp = vanilla(value_, bp, blk.end);
            if (bp == blk.end)
                continue;

            size_t sp = 0;
            size_t bs = bp;

            while (sp < s.length && bp < value_.length && bp < blk.end)
            {
                bool isHtmlEntity = false;
                int c;
                if (value_[bp] == '&')
                {
                    int qc = quoteChar(value_[bp + 1 .. $]);
                    if (qc < 0)
                        c = '&';
                    else
                    {
                        auto entityEnd = value_[bp + 1 .. $].indexOf(';');
                        if (entityEnd >= 0)
                        {
                            isHtmlEntity = true;
                            c = qc;
                            bp = bp + 1 + entityEnd;
                        }
                        else
                            c = '&';
                    }
                }
                else
                    c = value_[bp];

                if (c == '\n')
                    c = ' ';

                if (c > 0x20 && c < 0x80 && toLower(s[sp]) == toLower(cast(char) c))
                {
                    sp++;
                    bp = vanilla(value_, bp + 1, blk.end);
                }
                else if (isHtmlEntity)
                {
                    size_t idx = sp;
                    dchar dc = decode(s, idx);
                    if (cast(int) dc == c)
                    {
                        sp = idx;
                        bp = vanilla(value_, bp + 1, blk.end);
                    }
                    else
                    {
                        sp = 0;
                        bs = vanilla(value_, bs + 1, blk.end);
                        bp = bs;
                    }
                }
                else if (cast(int) s[sp] == c)
                {
                    sp++;
                    bp = vanilla(value_, bp + 1, blk.end);
                }
                else
                {
                    sp = 0;
                    bs = vanilla(value_, bs + 1, blk.end);
                    bp = bs;
                }
            }

            if (sp >= s.length)
            {
                topline(blk.y - blk.h);
                return cast(int) bs;
            }
        }

        return -1;
    }

    void link(HelpFunc fn)
    {
        linkFunc_ = fn;
    }

    string filename() const => filename_;
    string directory() const => directory_;
    string title() const => title_;

    // ---- Rendering attributes ----

    int size() const => size_;

    void textcolor(Color c)
    {
        if (textcolor_ == defcolor_)
            textcolor_ = c;
        defcolor_ = c;
    }

    Color textcolor() const => defcolor_;

    void textfont(Font f)
    {
        textfont_ = f;
        format();
    }

    Font textfont() const => textfont_;

    void textsize(Fontsize s)
    {
        textsize_ = s;
        format();
    }

    Fontsize textsize() const => textsize_;

    void topline(string anchor)
    {
        auto tl = toLowerAscii(anchor) in targetLineMap_;
        topline(tl !is null ? *tl : 0);
    }

    void topline(int top)
    {
        if (value_ is null)
            return;

        int scrollsize = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
        if (size_ < (h() - scrollsize) || top < 0)
            top = 0;
        else if (top > size_)
            top = size_;

        topline_ = top;

        scrollbar_.value(topline_, h() - scrollsize, 0, size_);

        doCallback(CallbackReason.dragged);

        redraw();
    }

    int topline() const => topline_;

    void leftline(int left)
    {
        if (value_ is null)
            return;

        int scrollsize = scrollbarSize_ != 0 ? scrollbarSize_ : fl.core.scrollbarSize();
        if (hsize_ < (w() - scrollsize) || left < 0)
            left = 0;
        else if (left > hsize_)
            left = hsize_;

        leftline_ = left;

        hscrollbar_.value(leftline_, w() - scrollsize, 0, hsize_);

        redraw();
    }

    int leftline() const => leftline_;

    // ---- Text selection ----

    void clearSelection()
    {
        selected_ = false;
        selectionFirst_ = 0;
        selectionLast_ = 0;
        redraw();
    }

    void selectAll()
    {
        clearSelection();
        if (value_ is null)
            return;
        selectionFirst_ = 0;
        selectionLast_ = cast(int) value_.length;
        selected_ = true;
    }

    bool textSelected() const => selected_;

    /// Ported from `Fl_Help_View::Impl::copy()`: converts the selected
    /// span of raw HTML into readable plaintext (tags stripped, a
    /// handful mapped to newline/bullet substitutions via `command()`/
    /// `CMD()`, entities decoded) and puts it on the clipboard.
    int copy(int clipboard = 1)
    {
        import std.array : appender;
        import std.ascii : isWhite;
        import std.utf : encode;

        if (!selected_)
            return 0;

        auto d = appender!(char[])();
        int p = 0;
        bool pre = false;
        size_t i = 0;

        while (i < value_.length)
        {
            char c = value_[i];
            i++;

            if (c == '<')
            {
                size_t cmdStart = i;
                bool sawGt = false;
                while (i < value_.length)
                {
                    char cc = value_[i];
                    i++;
                    if (cc == '>')
                    {
                        sawGt = true;
                        break;
                    }
                }
                if (!sawGt)
                    break;

                string src;
                switch (command(value_[cmdStart .. $]))
                {
                case CMD('p', 'r', 'e', 0):
                    pre = true;
                    break;
                case CMD('/', 'p', 'r', 'e'):
                    pre = false;
                    break;
                case CMD('t', 'd', 0, 0):
                case CMD('p', 0, 0, 0):
                case CMD('/', 'p', 0, 0):
                case CMD('b', 'r', 0, 0):
                    src = "\n";
                    break;
                case CMD('l', 'i', 0, 0):
                    src = "\n * ";
                    break;
                case CMD('/', 'h', '1', 0):
                case CMD('/', 'h', '2', 0):
                case CMD('/', 'h', '3', 0):
                case CMD('/', 'h', '4', 0):
                case CMD('/', 'h', '5', 0):
                case CMD('/', 'h', '6', 0):
                case CMD('t', 'r', 0, 0):
                case CMD('h', '1', 0, 0):
                case CMD('h', '2', 0, 0):
                case CMD('h', '3', 0, 0):
                case CMD('h', '4', 0, 0):
                case CMD('h', '5', 0, 0):
                case CMD('h', '6', 0, 0):
                    src = "\n\n";
                    break;
                case CMD('d', 't', 0, 0):
                    src = "\n ";
                    break;
                case CMD('d', 'd', 0, 0):
                    src = "\n - ";
                    break;
                default:
                    break;
                }

                int n = cast(int) i;
                if (src !is null && n > selectionFirst_ && n <= selectionLast_)
                {
                    d.put(src);
                    char lastC = src[$ - 1];
                    p = isWhite(lastC) ? ' ' : lastC;
                }
                continue;
            }

            size_t s2 = i;
            int cp = c;
            bool wasEntity = false;
            if (c == '&')
            {
                int xx = quoteChar(value_[i .. $]);
                if (xx >= 0)
                {
                    cp = xx;
                    while (i < value_.length)
                    {
                        char ch2 = value_[i];
                        i++;
                        if (ch2 == ';')
                        {
                            wasEntity = true;
                            break;
                        }
                    }
                }
            }

            int n2 = cast(int) s2;
            if (n2 > selectionFirst_ && n2 <= selectionLast_)
            {
                if (!pre && cp > 0 && cp < 0x80 && isWhite(cast(char) cp))
                    cp = ' ';
                if (!(p == ' ' && cp == ' '))
                {
                    if (wasEntity)
                    {
                        char[4] tmp;
                        size_t enc = encode(tmp, cast(dchar) cp);
                        d.put(tmp[0 .. enc]);
                    }
                    else
                        d.put(cast(char) cp);
                    p = cp;
                }
            }
            if (n2 > selectionLast_)
                break;
        }

        fl.core.copy(d.data.idup, clipboard);
        return 1;
    }

    // ---- Scroll bars ----

    int scrollbarSize() const => scrollbarSize_;

    void scrollbarSize(int newSize)
    {
        scrollbarSize_ = newSize;
    }
}

version (unittest)
{
    import fl.group : FlGroup;

    private void resetGroup()
    {
        FlGroup.current(null);
    }
}

unittest
{
    // atoiLike(): tolerant leading-digit-run parse, matching atoi()/
    // strtol()'s "stop at first invalid char, default 0" behavior.
    assert(atoiLike("42") == 42);
    assert(atoiLike("42;") == 42);
    assert(atoiLike("-5") == -5);
    assert(atoiLike("") == 0);
    assert(atoiLike("abc") == 0);
    assert(atoiLike("  7") == 7);
}

unittest
{
    // getAttr(): present-with-value, present-without-value (boolean
    // attribute), absent, quoted values (both quote styles).
    assert(getAttr(" HREF=foo.html ", "HREF") == "foo.html");
    assert(getAttr(" HREF='foo bar.html' ", "HREF") == "foo bar.html");
    assert(getAttr(" HREF=\"foo.html\" ", "HREF") == "foo.html");
    assert(getAttr(" href=FOO.HTML ", "HREF") == "FOO.HTML"); // case-insensitive name
    assert(getAttr(" NOSHADE ", "NOSHADE") == "");
    assert(getAttr(" HREF=foo.html ", "TARGET") is null);
    assert(getAttr(" HREF=foo.html TARGET=bar ", "TARGET") == "bar");
}

unittest
{
    // getLength(): absolute values and %-suffixed values against an
    // injected hsize_/scrollbarSize_ (not width()-dependent).
    auto v = new HelpView(0, 0, 200, 100);
    scope (exit)
        resetGroup();

    v.hsize_ = 200;
    v.scrollbarSize_ = 20;
    assert(v.getLength("50") == 50);
    assert(v.getLength("") == 0);
    assert(v.getLength("50%") == (50 * (200 - 20)) / 100);
    assert(v.getLength("150%") == (100 * (200 - 20)) / 100); // clamped to 100%
    assert(v.getLength("-10%") == 0); // clamped to 0%
}

unittest
{
    // getColor(): named lookup (HTML4 values, not X11's), #RRGGBB,
    // #RGB shorthand, and the "unrecognized name falls back to the
    // passed-in default" case.
    assert(getColor("red", 0) == rgbColor(0xff, 0x00, 0x00));
    assert(getColor("green", 0) == rgbColor(0x00, 0x80, 0x00)); // HTML green, not X11's
    assert(getColor("#ff8000", 0) == rgbColor(0xff, 0x80, 0x00));
    assert(getColor("#f80", 0) == rgbColor(0xff, 0x88, 0x00));
    assert(getColor("not-a-color", cast(Color) 42) == 42);
    assert(getColor(null, cast(Color) 42) == 42);
}

unittest
{
    // getAlign(): explicit ALIGN=, absent falls back to the passed-in
    // default, case-insensitive value matching.
    assert(getAlign("ALIGN=center", HelpView.Align.left) == HelpView.Align.center);
    assert(getAlign("ALIGN=RIGHT", HelpView.Align.left) == HelpView.Align.right);
    assert(getAlign("ALIGN=bogus", HelpView.Align.left) == HelpView.Align.left);
    assert(getAlign("", HelpView.Align.right) == HelpView.Align.right);
}

unittest
{
    // urlScheme(): with/without skipSlashes, and the no-scheme case.
    assert(urlScheme("http://example.com") == 5);
    assert(urlScheme("http://example.com", true) == 7);
    assert(urlScheme("file:foo.html") == 5);
    assert(urlScheme("relative/path.html") == 0);
    assert(urlScheme("mailto:a@b.com") == 7);
}

unittest
{
    // toLowerAscii(): ASCII-only case folding.
    assert(toLowerAscii("Foo Bar") == "foo bar");
    assert(toLowerAscii("ALREADY-LOWER") == "already-lower");
}

unittest
{
    // vanilla(): skips one or more <...> tag blocks, stops at real text.
    string s = "<B>hi</B> there";
    assert(vanilla(s, 0, s.length) == 3); // "hi</B> there" -> 'h' at index 3
    assert(vanilla(s, 3, s.length) == 3); // already on real text
    string s2 = "<B><I>x</I></B>";
    assert(vanilla(s2, 0, s2.length) == 6); // skips both opening tags -> 'x'
    string s3 = "<B unclosed"; // no '>' anywhere -> tag never closes
    assert(vanilla(s3, 0, s3.length) == s3.length);
}

unittest
{
    // command(): packs up to 4 significant chars, stops at '>'/space/
    // end, returns 0 for a 5th significant char.
    assert(command("br>") == CMD('b', 'r', 0, 0));
    assert(command("p>") == CMD('p', 0, 0, 0));
    assert(command("pre>") == CMD('p', 'r', 'e', 0));
    assert(command("table>") == 0); // 5+ significant chars
    assert(command("TR>") == CMD('t', 'r', 0, 0)); // case-folded
}

unittest
{
    // quoteChar(): named entity, decimal, hex, unrecognized, no ';' at all.
    assert(quoteChar("amp; rest") == '&');
    assert(quoteChar("copy;") == 169);
    assert(quoteChar("#65;") == 65);
    assert(quoteChar("#x41;") == 0x41);
    assert(quoteChar("#X41;") == 0x41);
    assert(quoteChar("bogus;") == -1);
    assert(quoteChar("amp no semicolon") == -1);
}

unittest
{
    // MarginStack push/pop/current sequencing.
    HelpView.MarginStack m;
    assert(m.current() == 4);
    assert(m.push(10) == 14);
    assert(m.push(5) == 19);
    assert(m.pop() == 14);
    assert(m.pop() == 4);
    assert(m.pop() == 4); // underflow guard: stays at the last element
}

unittest
{
    // FontStack push/pop/count/top sequencing, including the
    // "popping the last element re-applies it instead" guard.
    HelpView.FontStack fs;
    fs.init_(times, 12, foregroundColor);
    assert(fs.count() == 1);
    fs.push(courierBold, 14, backgroundColor);
    assert(fs.count() == 2);
    Font f;
    Fontsize s;
    Color c;
    fs.top(f, s, c);
    assert(f == courierBold && s == 14 && c == backgroundColor);
    fs.pop(f, s, c);
    assert(fs.count() == 1);
    assert(f == times && s == 12 && c == foregroundColor);
    fs.pop(f, s, c); // underflow guard
    assert(fs.count() == 1);
    assert(f == times && s == 12 && c == foregroundColor);
}

unittest
{
    // EditBuffer: add()'s UTF-8 encoding, cmp()'s case-insensitive
    // whole-buffer match, and opIndex()'s past-the-end '\0' safety net
    // (relied on by format()'s `buf[1]`/`buf[2]` checks on short tags).
    HelpView.EditBuffer b;
    b ~= 'H';
    b ~= '1';
    assert(b.cmp("h1"));
    assert(!b.cmp("h2"));
    assert(b[0] == 'H');
    assert(b[1] == '1');
    assert(b[2] == '\0'); // past the end
    b.clear();
    b.add(cast(dchar) 0x20ac); // euro sign, U+20AC, UTF-8-encodes to 3 bytes
    assert(b.str() == "€");
}

unittest
{
    // Construction + trivial accessor round-trips, headless-safe (no
    // show()/draw() involved).
    auto v = new HelpView(0, 0, 300, 200);
    scope (exit)
        resetGroup();

    assert(v.value() is null);
    assert(v.textfont() == times);
    assert(v.textsize() == 12);
    assert(v.topline() == 0);
    assert(v.leftline() == 0);
    assert(!v.textSelected());

    v.scrollbarSize(5);
    assert(v.scrollbarSize() == 5);
    v.scrollbarSize(0);
    assert(v.scrollbarSize() == 0);
}

unittest
{
    // format(): structural sanity check via value(). Not asserting on
    // exact pixel positions -- headless width() falls back to a
    // fake fixed-width estimate (see this project's testing
    // convention note in CLAUDE.md), so only layout-independent facts
    // are checked: title parsing, that formatting doesn't crash on a
    // representative mix of tags (headings, lists, links, bold/
    // italic, an unresolvable <IMG>), that it produces more than one
    // block, and that a named target is registered and reachable via
    // topline(string).
    auto v = new HelpView(0, 0, 300, 200);
    scope (exit)
        resetGroup();

    v.value("<HTML><HEAD><TITLE>My Title</TITLE></HEAD>"
            ~ "<BODY><H1>Heading</H1>"
            ~ "<P>Hello <B>bold</B> and <I>italic</I> text with a "
            ~ "<A HREF=\"other.html\">link</A> and an entity: &amp;.</P>"
            ~ "<UL><LI>one</LI><LI>two</LI></UL>"
            ~ "<A NAME=\"marker\"></A>"
            ~ "<IMG SRC=\"missing.png\">"
            ~ "</BODY></HTML>");

    assert(v.title() == "My Title");
    assert(v.blocks_.length > 1);
    assert(v.linkList_.length == 1);
    assert(v.linkList_[0].filename_ == "other.html");
    assert(("marker" in v.targetLineMap_) !is null);

    v.topline("marker"); // must not crash, must resolve via targetLineMap_
    v.topline("no-such-target"); // falls back to topline(0), must not crash
    assert(v.topline() == 0);
}

unittest
{
    // format(): <TABLE>/<TR>/<TD>/<TH> -- Milestone 2. A bordered,
    // two-row/two-column table with a per-cell BGCOLOR: confirms real
    // column layout (cells land at different X positions), that
    // border/bgcolor actually reach the TD block (not just parsed and
    // dropped), and that a header cell doesn't crash TH's bold-font
    // branch. Not asserting on exact pixel values -- see the sibling
    // format() test's own note on headless width()'s fake metrics.
    auto v = new HelpView(0, 0, 400, 300);
    scope (exit)
        resetGroup();

    v.value("<HTML><BODY>"
            ~ "<TABLE BORDER=1>"
            ~ "<TR><TH>Name</TH><TH>Value</TH></TR>"
            ~ "<TR><TD BGCOLOR=\"#ff0000\">alpha</TD><TD>1</TD></TR>"
            ~ "<TR><TD>beta</TD><TD>2</TD></TR>"
            ~ "</TABLE>"
            ~ "<P>After the table</P>"
            ~ "</BODY></HTML>");

    assert(v.blocks_.length > 1);

    // At least one block carries the table's BORDER=1 and at least
    // one carries the red BGCOLOR -- i.e. TD/TH really reached
    // addBlock()'s border/bgcolor parameters, not just parsed and
    // discarded.
    bool anyBorder = false;
    bool anyBgcolor = false;
    foreach (ref const blk; v.blocks_)
    {
        if (blk.border != 0)
            anyBorder = true;
        if (blk.bgcolor == rgbColor(255, 0, 0))
            anyBgcolor = true;
    }
    assert(anyBorder);
    assert(anyBgcolor);

    // Cells in different columns must land at different X positions
    // (real column layout, not everything collapsed to column 0).
    int[] cellXs;
    foreach (ref const blk; v.blocks_)
        if (blk.border != 0)
            cellXs ~= blk.x;
    assert(cellXs.length >= 4);
    bool sawDifferentX = false;
    foreach (xVal; cellXs[1 .. $])
        if (xVal != cellXs[0])
            sawDifferentX = true;
    assert(sawDifferentX);

    // Text after </TABLE> is still reachable/laid out (the table
    // branch's retry-on-overflow path didn't get stuck).
    assert(v.find("After the table") >= 0);

    v.draw(); // headless smoke check for the new TD/TH bgcolor/border rect drawing
}

unittest
{
    // formatTable(): a document with only <TR>/<TD> and no enclosing
    // <TABLE> at all -- the (buf.cmp("TD")||buf.cmp("TH")) && row
    // guards mean bare TR/TD tags outside a table are simply ignored
    // (row stays 0), same "unrecognized tag" fallback as any other
    // unknown tag. Must not crash.
    auto v = new HelpView(0, 0, 300, 200);
    scope (exit)
        resetGroup();

    v.value("<HTML><BODY><TD>orphan cell</TD><TR>orphan row</TR></BODY></HTML>");
    assert(v.find("orphan cell") >= 0);
}

unittest
{
    // find(): a real word matches (and the returned offset really
    // points at it in value()), a tag-shaped search string never
    // matches (find() skips over HTML tags via vanilla()), and a
    // nonexistent word returns -1.
    auto v = new HelpView(0, 0, 300, 200);
    scope (exit)
        resetGroup();

    v.value("<HTML><BODY><P>Hello world, this is a test.</P></BODY></HTML>");

    auto idx = v.find("world");
    assert(idx >= 0);
    assert(v.value()[idx .. idx + 5] == "world");

    assert(v.find("BODY") == -1); // tag text is skipped, never matched
    assert(v.find("nonexistent") == -1);

    assert(v.find("Hello World") >= 0); // ASCII case-insensitive
}

unittest
{
    // copy(): selecting the whole document and copying strips tags,
    // maps a couple of block tags to newlines, and decodes entities --
    // landing in fl.core's in-process clipboard buffer (confirmed
    // headless-safe by fl.text_display.d's own unittest use of
    // fl.core.copy()).
    import fl.core : resetForTest, clipboardContents;

    FlGroup.current(null);
    resetForTest();

    auto v = new HelpView(0, 0, 300, 200);
    scope (exit)
        resetGroup();

    v.value("<HTML><BODY><P>one &amp; two</P><P>three</P></BODY></HTML>");
    assert(v.copy(1) == 0); // nothing selected yet

    v.selectAll();
    assert(v.copy(1) == 1);

    string pasted = clipboardContents(1);
    assert(pasted.length > 0);

    import std.algorithm.searching : canFind;

    assert(pasted.canFind("one & two")); // entity decoded
    assert(pasted.canFind("three"));
    assert(!pasted.canFind("<P>")); // tags stripped
}

unittest
{
    // load(): the file:/local path -- a real file on disk, loaded and
    // formatted; a missing file produces a real in-view error page
    // (return -1) instead of crashing.
    import std.file : write, remove, tempDir;
    import std.path : buildPath;

    auto v = new HelpView(0, 0, 300, 200);
    scope (exit)
        resetGroup();

    auto path = buildPath(tempDir(), "fldtk-help-view-test.html");
    write(path, "<HTML><HEAD><TITLE>Loaded</TITLE></HEAD><BODY>Hi there</BODY></HTML>");
    scope (exit)
        remove(path);

    assert(v.load(path) == 0);
    assert(v.title() == "Loaded");
    assert(v.filename() == path);

    assert(v.load(path ~ "-does-not-exist") == -1);
    assert(v.title() == "Error");
}
