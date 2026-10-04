/*
 * Ported from FL/Fl_File_Icon.H + src/Fl_File_Icon.cxx +
 * src/Fl_File_Icon2.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * A small vector-icon format: a `short[]` array of opcodes (COLOR,
 * LINE, CLOSEDLINE, POLYGON, OUTLINEPOLYGON, VERTEX, END) drawn
 * through fl.draw's transform-stack + vertex-path primitives
 * (pushMatrix()/fl_translate()/fl_scale()/fl_begin_*()/vertex()/
 * fl_end_*()/popMatrix()), all of which are real in this port
 * already -- this module needed no new fl.draw primitives, unlike most
 * of what's been ported recently.
 *
 * Deliberate deviations:
 *
 *  - `void* item`/pointer-returning `add()` becomes an `int` index into
 *    a plain `short[]` -- `data_` is a GC-managed growable D array, not
 *    a hand-`malloc()`/`realloc()`'d C buffer, so there's no pointer to
 *    return or invalidate; every FLTK call site that used the
 *    returned pointer only ever did so to compute an *offset* back into
 *    the array later (`load_fti()`'s `bgnoutlinepolygon` bookkeeping),
 *    which an `int` index already gives directly.
 *
 *  - **No destructor.** FLTK's `~Fl_File_Icon()` unlinks itself
 *    from the process-wide `first_` list and frees `data_`. Every real
 *    call site in FLTK itself (and in this port) only ever constructs
 *    `Fl_File_Icon`/`FileIcon` instances as permanent, program-lifetime
 *    registrations (`new Fl_File_Icon(...)` with no matching `delete`
 *    anywhere FLTK either) -- there's no reachable code path that
 *    needs one removed early, so this port doesn't add a destructor
 *    just to mirror one FLTK never actually exercises this way.
 *    The GC reclaims `data_` on its own either way.
 *
 *  - **`draw()`'s trailing (array-ends-without-a-matching-END)
 *    POLYGON/OUTLINEPOLYGON close uses `endComplexPolygon()`, not
 *    `endPolygon()` like FLTK's literal text.** FLTK gets
 *    away with calling the "simple polygon" end function on a path it
 *    opened with `begin_complex_polygon()` only because
 *    `Fl_Xlib_Graphics_Driver` tracks "what kind of path is currently
 *    open" in one shared `what` field that both begin functions set
 *    the same way -- `end_polygon()` and `end_complex_polygon()` are
 *    actually interchangeable there. This port's `fl.draw` doesn't
 *    share that field (see its own `beginComplexPolygon()` doc
 *    comment: "reusing VertexKind.complexPolygon ... since D has no
 *    shared mutable `what` field"), so `endPolygon()` is strictly
 *    guarded to only fire after `beginPolygon()` -- calling it here
 *    would silently no-op instead of drawing anything. Since every
 *    open primitive this function ever produces via POLYGON/
 *    OUTLINEPOLYGON was opened with `beginComplexPolygon()`,
 *    calling the matching `endComplexPolygon()` in both the
 *    normal (END-terminated) and trailing-fallback close paths is the
 *    faithful behavior, not a divergence from it -- it's what makes
 *    the trailing-fallback case actually draw at all. (This also means
 *    the END-terminated and trailing-fallback cases now share one
 *    closing helper instead of FLTK's two near-duplicate switch
 *    blocks.)
 *
 *  - **`load_image()` is real**: see `loadImage()`'s own doc comment
 *    for the full port, including how it sidesteps re-deriving XPM
 *    colormap parsing by reusing the existing
 *    `RGBImage(const(Pixmap), Color)` conversion constructor.
 *
 *  - **`load_system_icons()`'s cascade is faithful, including the
 *    legacy KDE-mimelnk/GNOME/CDE/SGI branches**, even though every one
 *    of those `fl_access()`/`exists()` guards will fail on essentially
 *    any system built after ~2005 (`/opt/kde`'s `share/mimelnk`,
 *    `/usr/share/icons/folder.xpm`, `/usr/dt/appconfig/icons`,
 *    `/usr/lib/filetype` are all pre-XDG desktop-environment layouts).
 *    In practice this means the function falls straight through to the
 *    final `else` branch on a modern Linux box: three built-in
 *    *vector* icons (plain/image/dir, transcribed verbatim from
 *    FLTK's inline `short[]` literals below) that need no
 *    `fl.image` support at all and draw real pixels today. The KDE/
 *    GNOME/CDE/SGI branches are kept for fidelity (cheap, no new
 *    dependency beyond what `load()`/`loadImage()`/`loadFti()` already
 *    need) but are effectively dead code on any modern Linux system.
 *
 *  - **KDE-mimelnk scanning uses `std.file.dirEntries()`/`readText()`**
 *    instead of `fl_filename_list()`/byte-at-a-time `fgets()`, matching
 *    the same "concrete D stdlib over hand-rolled C" substitution
 *    `fl.file_browser`'s `loadDirectory()` already established.
 *
 *  - **A likely FLTK bug, ported faithfully rather than fixed**:
 *    `load_kde_mimelnk()`'s "KDE 1.x icons" fallback branch builds the
 *    icon path from `tmp` -- but `tmp` is the byte buffer from the
 *    file's *last `fgets()` line*, not a directory path; it was never
 *    assigned anything path-like. This looks like a copy/paste leftover
 *    (the variable name "tmp" back when it may have held a scratch
 *    directory string) rather than intentional. Noted as an
 *    `FLTK_ISSUES.md` candidate. Since this branch is already
 *    unreachable on any modern system (it only runs for KDE 1.x, which
 *    additionally requires the *outer* `!fl_access(icondir, F_OK)`
 *    check above it to have failed, i.e. no KDE 2/3 icon theme
 *    directory was found), this port reproduces the same "use the last
 *    line read" value (renamed `lastLine` here) rather than silently
 *    correcting it -- it will almost always fail the subsequent
 *    existence check either way.
 *
 *  - **`Fl_File_Icon::label(Fl_Widget*)`/`labeltype()`**: ported as
 *    `FileIcon.label(Widget)`, wired into `fl.widget`'s `Label` struct
 *    via a new `Labeltype.iconLabel` case in `Label.draw()` (the enum
 *    value already existed, reserved but undispatched) -- same pattern
 *    already established for `Labeltype.multiLabel`/`fl.multi_label`.
 *    `Label.measure()` needed no change: an icon label's `text` field
 *    is always empty, and the existing `if (text.length == 0)` fallback
 *    already yields `(0, 0)`, which is what this port uses instead of
 *    FLTK's `fl_normal_measure()` -- FLTK's own default-measure
 *    fallback (`Fl::set_labeltype(_FL_ICON_LABEL, ..., 0)` passes a
 *    null measure function) measures `o->value` as if it were text,
 *    but `o->value` is actually an `Fl_File_Icon*` reinterpreted as
 *    `const char*` -- reading raw object bytes as UTF-8 text. Nothing
 *    in FLTK itself (or this port) actually calls
 *    `Fl_File_Icon::label()`/relies on its measured size, so this port
 *    doesn't reproduce that undefined-looking read.
 */
module fl.file_icon;

import std.algorithm : startsWith;
import std.array : replace;
import std.ascii : isAlpha, isWhite;
import std.file : exists, dirEntries, DirEntry, SpanMode, readText, isDir;
import std.math : round;
import std.path : baseName;
import std.process : environment;
import std.string : splitLines;

import fl.enumerations : Color, gray, black, white, red, green, blue, dark3;
import fl.filename : filenameName, filenameExt, filenameMatch;
import fl.widget : Widget;
import fldraw = fl.draw;

/// Special color value meaning "use the caller's `ic` parameter" --
/// `FL_ICON_COLOR` FLTK.
enum Color iconColor = 0xffffffff;

/// File types a FileIcon can be registered against -- `Fl_File_Icon`'s
/// anonymous `ANY`/`PLAIN`/`FIFO`/`DEVICE`/`LINK`/`DIRECTORY` enum. A
/// closed, non-combinable tag set (never combined with `|`), so a real
/// D `enum`, matching `CLAUDE.md`'s convention.
enum FileType
{
    any,
    plain,
    fifo,
    device,
    link,
    directory,
}

/// Data opcodes stored inline in `data_` alongside raw coordinate/color
/// shorts -- `Fl_File_Icon`'s anonymous `END`/`COLOR`/`LINE`/
/// `CLOSEDLINE`/`POLYGON`/`OUTLINEPOLYGON`/`VERTEX` enum. Declared with
/// base type `short` so opcode values drop into a plain `short[]`
/// (which also holds arbitrary vertex/color data) without a cast.
enum Op : short
{
    end,
    colorOp,
    lineOp,
    closedLineOp,
    polygonOp,
    outlinePolygonOp,
    vertexOp,
}

private enum short grayS = cast(short) gray;
private enum short blackS = cast(short) black;
private enum short whiteS = cast(short) white;
private enum short redS = cast(short) red;
private enum short greenS = cast(short) green;
private enum short blueS = cast(short) blue;
private enum short dark3S = cast(short) dark3;

/**
 * The FileIcon class manages icon images that can be used as labels in
 * other widgets and as icons in FileBrowser. Ported from `Fl_File_Icon`.
 */
class FileIcon
{
    private static FileIcon first_;

    private FileIcon next_;
    private string pattern_;
    private FileType type_;
    private short[] data_;

    /// Creates a new icon, prepending it to the process-wide registry
    /// (`first()`/`next()` walk newest-first, matching FLTK's
    /// prepend-to-head list).
    this(string pattern, FileType type, const(short)[] data = null)
    {
        pattern_ = pattern;
        type_ = type;
        data_ = data.dup;

        next_ = first_;
        first_ = this;
    }

    /// Adds a single data value, returning its index in `value()`.
    int add(short d)
    {
        data_ ~= d;
        return cast(int) data_.length - 1;
    }

    /// Adds a color value (COLOR opcode + hi/lo shorts), returning the
    /// index of the opcode itself.
    int addColor(Color c)
    {
        int idx = add(Op.colorOp);
        add(cast(short)(c >> 16));
        add(cast(short) c);
        return idx;
    }

    /// Adds a vertex (integer form, 0-10000 per axis), returning the
    /// index of the VERTEX opcode itself.
    int addVertex(int x, int y)
    {
        int idx = add(Op.vertexOp);
        add(cast(short) x);
        add(cast(short) y);
        return idx;
    }

    /// ditto, floating-point form (0.0-1.0 per axis).
    int addVertex(float x, float y)
    {
        int idx = add(Op.vertexOp);
        add(cast(short)(x * 10000.0));
        add(cast(short)(y * 10000.0));
        return idx;
    }

    /// Clears all icon data (keeps pattern/type/registration).
    void clear() { data_.length = 0; }

    /// The data array for the icon.
    inout(short)[] value() inout { return data_; }

    /// The number of words of data used by the icon.
    int size() const { return cast(int) data_.length; }

    /// The filename matching pattern for the icon.
    string pattern() const { return pattern_; }

    /// The filetype this icon is associated with.
    FileType type() const { return type_; }

    /// The next icon in the registry (see `first()`).
    inout(FileIcon) next() inout { return next_; }

    /// The first icon in the registry.
    static FileIcon first() { return first_; }

    /// Finds an icon matching `filename`/`filetype`. Ported from
    /// `Fl_File_Icon::find()`.
    static FileIcon find(string filename, FileType filetype = FileType.any)
    {
        if (filetype == FileType.any)
            filetype = fileType(filename);

        string name = filenameName(filename);

        for (auto cur = first_; cur !is null; cur = cur.next_)
            if ((cur.type_ == filetype || cur.type_ == FileType.any)
                && (filenameMatch(filename, cur.pattern_) || filenameMatch(name, cur.pattern_)))
                return cur;

        return null;
    }

    /**
     * Draws the icon within (x, y, w, h). Ported from
     * `Fl_File_Icon::draw()` -- see the module comment for the one
     * deliberate deviation (`endComplexPolygon()` instead of
     * `endPolygon()` for the trailing-unterminated-array case).
     */
    void draw(int x, int y, int w, int h, Color ic, bool active = true) const
    {
        if (data_.length == 0) return;

        double scale = w < h ? w : h;

        fldraw.pushMatrix();
        fldraw.fl_translate(cast(double) x + 0.5 * (cast(double) w - scale),
                             cast(double) y + 0.5 * (cast(double) h + scale));
        fldraw.fl_scale(scale, -scale);

        size_t i = 0;
        size_t dend = data_.length;
        size_t prim = size_t.max; // NULL sentinel, matching FLTK's `prim`
        Color c = ic;

        fldraw.fl_color(active ? c : fldraw.inactive(c));

        while (i < dend)
        {
            switch (data_[i])
            {
            case Op.end:
                if (prim != size_t.max)
                    closePrimitive(prim, ic, c, active);
                prim = size_t.max;
                i++;
                break;

            case Op.colorOp:
                c = decodeColor(data_[i + 1], data_[i + 2]);
                if (c == iconColor) c = ic;
                if (!active) c = fldraw.inactive(c);
                fldraw.fl_color(c);
                i += 3;
                break;

            case Op.lineOp:
                prim = i;
                i++;
                fldraw.beginLine();
                break;

            case Op.closedLineOp:
                prim = i;
                i++;
                fldraw.beginLoop();
                break;

            case Op.polygonOp:
                prim = i;
                i++;
                fldraw.beginComplexPolygon();
                break;

            case Op.outlinePolygonOp:
                prim = i;
                i += 3;
                fldraw.beginComplexPolygon();
                break;

            case Op.vertexOp:
                if (prim != size_t.max)
                    fldraw.vertex(data_[i + 1] * 0.0001, data_[i + 2] * 0.0001);
                i += 3;
                break;

            default:
                i++;
            }
        }

        // If we still have an open primitive, close it -- shares the
        // same helper as the END case above, see the module comment.
        if (prim != size_t.max)
            closePrimitive(prim, ic, c, active);

        fldraw.popMatrix();
    }

    /// Closes the primitive started at `data_[primIdx]`, shared by both
    /// the normal END-terminated case and the trailing-unterminated-
    /// array fallback in draw() above (see the module comment for why
    /// these two FLTK code paths collapse into one here).
    private void closePrimitive(size_t primIdx, Color ic, Color c, bool active) const
    {
        switch (data_[primIdx])
        {
        case Op.lineOp:
            fldraw.endLine();
            break;

        case Op.closedLineOp:
            fldraw.endLoop();
            break;

        case Op.polygonOp:
            fldraw.endComplexPolygon();
            break;

        case Op.outlinePolygonOp:
            fldraw.endComplexPolygon();

            Color oc = decodeColor(data_[primIdx + 1], data_[primIdx + 2]);
            Color outlineColor = (oc == iconColor) ? ic : oc;
            fldraw.fl_color(active ? outlineColor : fldraw.inactive(outlineColor));

            fldraw.beginLoop();
            size_t v = primIdx + 3;
            while (v + 2 < data_.length && data_[v] == Op.vertexOp)
            {
                fldraw.vertex(data_[v + 1] * 0.0001, data_[v + 2] * 0.0001);
                v += 3;
            }
            fldraw.endLoop();
            fldraw.fl_color(c);
            break;

        default:
            break;
        }
    }

    /// Associates this icon with `w`'s label (`Labeltype.iconLabel`).
    /// See the module comment for how this wires into `fl.widget`'s
    /// `Label.draw()`.
    void label(Widget w)
    {
        w.label(this);
    }

    /// Loads an icon file, dispatching on extension (`.fti` -> vector
    /// format, anything else -> raster image). Returns success/failure
    /// -- FLTK's `void` return + `Fl::warning()` call has no
    /// equivalent here (no such logging subsystem is ported), matching
    /// the bool-returning convention `fl.file_browser.loadDirectory()`
    /// already established for the same reason.
    bool load(string f)
    {
        string ext = filenameExt(f);
        if (ext == ".fti")
            return loadFti(f);
        else
            return loadImage(f);
    }

    /**
     * Loads an SGI-format `.fti` vector-icon file. Faithful port of
     * `Fl_File_Icon::load_fti()`'s hand-rolled recursive-descent
     * scanner, reading from an in-memory string (`std.file.readText()`)
     * instead of a byte-at-a-time `getc()` loop -- same "no reason to
     * hand-roll what Phobos already does" substitution as elsewhere in
     * this port, with no behavioral difference (the grammar is scanned
     * left-to-right either way).
     */
    bool loadFti(string path)
    {
        string content;
        try content = readText(path);
        catch (Exception) return false;

        size_t i = 0;
        size_t n = content.length;
        int outline = -1; // -1 == "no outline in progress" (FLTK: 0, but 0 is a valid index here -- see the ctor doc comment on int-index-not-pointer)

        while (i < n)
        {
            char ch = content[i];

            if (isWhite(ch)) { i++; continue; }

            if (ch == '#')
            {
                while (i < n && content[i] != '\n') i++;
                if (i < n) i++;
                continue;
            }

            if (!isAlpha(ch)) break;

            size_t cmdStart = i;
            while (i < n && content[i] != '(') i++;
            if (i >= n) break;
            string command = content[cmdStart .. i];
            i++; // skip '('

            size_t paramStart = i;
            while (i < n && content[i] != ')') i++;
            if (i >= n) break;
            string params = content[paramStart .. i];
            i++; // skip ')'

            if (i >= n || content[i] != ';') break;
            i++; // skip ';'

            if (command == "color")
            {
                addColor(parseFtiColor(params));
            }
            else if (command == "bgnline")
                add(Op.lineOp);
            else if (command == "bgnclosedline")
                add(Op.closedLineOp);
            else if (command == "bgnpolygon")
                add(Op.polygonOp);
            else if (command == "bgnoutlinepolygon")
            {
                add(Op.outlinePolygonOp);
                outline = add(0);
                add(0);
            }
            else if (command == "endoutlinepolygon" && outline >= 0)
            {
                Color cval = parseFtiColor(params);
                data_[outline] = cast(short)(cval >> 16);
                data_[outline + 1] = cast(short) cval;
                outline = -1;
                add(Op.end);
            }
            else if (command.length >= 3 && command[0 .. 3] == "end")
                add(Op.end);
            else if (command == "vertex")
            {
                float x, y;
                if (!parseFtiVertex(params, x, y)) break;
                addVertex(cast(int) round(x * 100.0), cast(int) round(y * 100.0));
            }
            else
                break; // unknown command -- matches FLTK's error-and-stop
        }

        return true; // FLTK always returns 0 (success) even after a parse error mid-file, just stops scanning
    }

    /**
     * Loads a raster image icon from a file, approximating it as a
     * grid of same-color POLYGONs (one run of horizontally-adjacent
     * same-color pixels per polygon, matching FLTK's own
     * run-length approach exactly). Ported from `Fl_File_Icon::
     * load_image()` (`src/Fl_File_Icon2.cxx`).
     *
     * Deliberate simplification: FLTK dispatches on `img->count()`
     * (1 for a plain RGB(A) image, >1 for an XPM colormap+index
     * buffer) and hand-parses the XPM colormap itself (`sscanf`/hex
     * parsing/`"c "` color-string lookup, ~140 lines). This port's
     * `fl.image` deliberately has no generic `count()`/`data()`
     * accessor at all (every real caller already knows its concrete
     * image type -- see that module's own top comment), so there is no
     * XPM-vs-RGB branch to dispatch on here in the first place: an XPM
     * file loads as a `fl.pixmap.Pixmap` (`fl.xpm_image.XPMImage`
     * `: Pixmap`), which converts to a real, already-decoded RGBA
     * `RGBImage` via the existing `RGBImage(const(Pixmap), Color)`
     * constructor (the same `convertPixmap()` routine `Pixmap.draw()`
     * itself uses) -- reusing that instead of re-deriving XPM
     * colormap parsing a second time. Every pixel format then walks
     * the single unified RGB(A) loop below, matching FLTK's own
     * `count()==1` branch letter for letter. A 1-bit `fl.bitmap.Bitmap`
     * (from an XBM file) isn't handled -- FLTK's own generic
     * `d()`-based switch has no real case for `d()==0` either (its
     * `default:` branch would read raw packed-bit bytes as if they
     * were per-pixel RGBA, i.e. garbage), and no real call site
     * (`load_system_icons()`'s own cascade included) ever loads an XBM
     * file through this path, so returning `false` here is strictly
     * safer than FLTK's own undefined behavior for a case nothing
     * actually exercises.
     */
    bool loadImage(string ifile)
    {
        import fl.shared_image : SharedImage;
        import fl.image : RGBImage;
        import fl.pixmap : Pixmap;

        auto img = SharedImage.get(ifile);
        if (img is null) return false;
        scope (exit) img.release();

        if (img.w() == 0 || img.h() == 0) return false;

        auto rgb = cast(RGBImage) img.image();
        if (rgb is null)
        {
            auto pxm = cast(Pixmap) img.image();
            if (pxm !is null) rgb = new RGBImage(pxm);
        }
        if (rgb is null || rgb.array.length == 0) return false;

        int w = rgb.dataW();
        int h = rgb.dataH();
        int d = rgb.d();
        int ld = rgb.ld() ? rgb.ld() : w * d;
        const(ubyte)[] data = rgb.array;

        for (int y = 0; y < h; y++)
        {
            const(ubyte)[] row = data[y * ld .. $];
            int startx = 0;
            int x;
            Color c = cast(Color) -1;

            for (x = 0; x < w; x++)
            {
                const(ubyte)[] px = row[x * d .. $];
                Color temp;
                switch (d)
                {
                case 1:
                    temp = fldraw.rgbColor(px[0], px[0], px[0]);
                    break;
                case 2:
                    temp = px[1] > 127 ? fldraw.rgbColor(px[0], px[0], px[0]) : cast(Color) -1;
                    break;
                case 3:
                    temp = fldraw.rgbColor(px[0], px[1], px[2]);
                    break;
                default:
                    temp = px[3] > 127 ? fldraw.rgbColor(px[0], px[1], px[2]) : cast(Color) -1;
                    break;
                }

                if (temp != c)
                {
                    if (x > startx && c != cast(Color) -1) addIconPolygonRow(c, startx, x, y, w, h);
                    c = temp;
                    startx = x;
                }
            }

            if (x > startx && c != cast(Color) -1) addIconPolygonRow(c, startx, x, y, w, h);
        }

        return true;
    }

    /// One horizontal run of same-color pixels, emitted as a single
    /// POLYGON -- shared by both the mid-row and end-of-row flush
    /// points in loadImage() above, matching FLTK's own
    /// (duplicated inline, there) vertex math exactly.
    private void addIconPolygonRow(Color c, int startx, int x, int y, int w, int h)
    {
        addColor(c);
        add(Op.polygonOp);
        addVertex(startx * 9000 / w + 1000, 9500 - y * 9000 / h);
        addVertex(x * 9000 / w + 1000, 9500 - y * 9000 / h);
        addVertex(x * 9000 / w + 1000, 9500 - (y + 1) * 9000 / h);
        addVertex(startx * 9000 / w + 1000, 9500 - (y + 1) * 9000 / h);
        add(Op.end);
    }
}

private Color decodeColor(short hi, short lo)
{
    return (cast(Color) cast(ushort) hi << 16) | cast(Color) cast(ushort) lo;
}

/// Parses a `.fti` color parameter: the three symbolic names, or a
/// signed decimal (negative == composite/averaged color, matching
/// FLTK's `atoi()` + sign check).
private Color parseFtiColor(string params)
{
    if (params == "iconcolor") return iconColor;
    if (params == "shadowcolor") return dark3;
    if (params == "outlinecolor") return black;

    int c = atoiLike(params);
    if (c < 0)
    {
        c = -c;
        return fldraw.colorAverage(cast(Color)(c >> 4), cast(Color)(c & 15), 0.5f);
    }
    return cast(Color) c;
}

/// `atoi()`-equivalent: leading whitespace, optional sign, digits;
/// never throws, returns 0 for non-numeric input. `std.conv.parse!int()`
/// already tolerates trailing garbage (stops at the first invalid
/// character instead of requiring the whole string to convert, unlike
/// `std.conv.to!int()`) -- `std.string.stripLeft()` handles the leading
/// whitespace, which `parse!int()` doesn't do on its own.
private int atoiLike(string s)
{
    import std.conv : parse, ConvException;
    import std.string : stripLeft;

    auto rest = stripLeft(s);
    try
        return parse!int(rest);
    catch (ConvException)
        return 0;
}

/// Parses a `.fti` "x,y" vertex parameter -- `sscanf(params, "%f,%f",
/// &x, &y)`'s equivalent, returning false (matching FLTK's `!= 2`
/// check) if either half doesn't parse.
private bool parseFtiVertex(string params, out float x, out float y)
{
    import std.string : indexOf;
    import std.conv : to, ConvException;

    auto comma = params.indexOf(',');
    if (comma < 0) return false;

    try
    {
        x = to!float(params[0 .. comma]);
        y = to!float(params[comma + 1 .. $]);
    }
    catch (ConvException) return false;

    return true;
}

/// Ported from `Fl_Posix_System_Driver::file_type()` -- no driver
/// abstraction exists in this port (matching the established
/// concrete-implementation convention). Uses `stat()`, not `lstat()`,
/// matching FLTK exactly -- including its own dead `S_ISLNK`
/// branch (a followed `stat()` can never itself report a symlink).
private FileType fileType(string filename)
{
    version (Posix)
    {
        import core.sys.posix.sys.stat : stat_t, stat, S_ISDIR, S_ISFIFO, S_ISCHR, S_ISBLK, S_ISLNK;
        import std.string : toStringz;

        stat_t st;
        if (stat(filename.toStringz, &st) == 0)
        {
            if (S_ISDIR(st.st_mode)) return FileType.directory;
            if (S_ISFIFO(st.st_mode)) return FileType.fifo;
            if (S_ISCHR(st.st_mode) || S_ISBLK(st.st_mode)) return FileType.device;
            if (S_ISLNK(st.st_mode)) return FileType.link;
            return FileType.plain;
        }
        return FileType.plain;
    }
    else
    {
        // No stat()-based fifo/device/symlink classification on Windows --
        // those are POSIX file-mode concepts with no clean equivalent, and
        // no consumer here needs anything beyond the directory/plain split.
        import std.file : isDir, FileException;

        try
        {
            if (isDir(filename)) return FileType.directory;
        }
        catch (FileException) { }
        return FileType.plain;
    }
}

// ---------------------------------------------------------------------
// load_system_icons() and its KDE-mimelnk-scanning helpers.
// ---------------------------------------------------------------------

private bool systemIconsLoaded = false;

/**
 * Loads all system-defined icons -- the KDE/GNOME/CDE/SGI cascade, or
 * (in practice, on any modern system -- see the module comment) the
 * three built-in vector icons below. Idempotent, matching FLTK's
 * `static int init` guard.
 */
void loadSystemIcons()
{
    if (systemIconsLoaded) return;
    systemIconsLoaded = true;

    string kdedir = environment.get("KDEDIR", "");
    if (kdedir.length == 0)
    {
        if (exists("/opt/kde")) kdedir = "/opt/kde";
        else if (exists("/usr/local/share/mimelnk")) kdedir = "/usr/local";
        else kdedir = "/usr";
    }

    string mimelnkDir = kdedir ~ "/share/mimelnk";

    static immutable string[] icondirs = ["Bluecurve", "crystalsvg", "default.kde", "hicolor"];

    if (exists(mimelnkDir))
    {
        // KDE icons.
        auto icon = new FileIcon("*", FileType.plain);

        string icondir;
        bool found = false;
        foreach (d; icondirs)
        {
            icondir = kdedir ~ "/share/icons/" ~ d;
            if (exists(icondir)) { found = true; break; }
        }

        string filename = found
            ? icondir ~ "/16x16/mimetypes/unknown.png"
            : kdedir ~ "/share/icons/unknown.xpm";
        if (exists(filename)) icon.loadImage(filename);

        icon = new FileIcon("*", FileType.link);
        filename = icondir ~ "/16x16/filesystems/link.png";
        if (exists(filename)) icon.loadImage(filename);

        loadKdeIcons(mimelnkDir, icondir);
    }
    else if (exists("/usr/share/icons/folder.xpm"))
    {
        // GNOME icons.
        auto icon = new FileIcon("*", FileType.plain);
        icon.loadImage("/usr/share/icons/page.xpm");

        icon = new FileIcon("*", FileType.directory);
        icon.loadImage("/usr/share/icons/folder.xpm");
    }
    else if (exists("/usr/dt/appconfig/icons"))
    {
        // CDE icons.
        auto icon = new FileIcon("*", FileType.plain);
        icon.loadImage("/usr/dt/appconfig/icons/C/Dtdata.m.pm");

        icon = new FileIcon("*", FileType.directory);
        icon.loadImage("/usr/dt/appconfig/icons/C/DtdirB.m.pm");

        icon = new FileIcon("core", FileType.plain);
        icon.loadImage("/usr/dt/appconfig/icons/C/Dtcore.m.pm");

        icon = new FileIcon("*.{bmp|bw|gif|jpg|pbm|pcd|pgm|ppm|png|ras|rgb|tif|xbm|xpm}", FileType.plain);
        icon.loadImage("/usr/dt/appconfig/icons/C/Dtimage.m.pm");

        icon = new FileIcon("*.{eps|pdf|ps}", FileType.plain);
        icon.loadImage("/usr/dt/appconfig/icons/C/Dtps.m.pm");

        icon = new FileIcon("*.ppd", FileType.plain);
        icon.loadImage("/usr/dt/appconfig/icons/C/DtPrtpr.m.pm");
    }
    else if (exists("/usr/lib/filetype"))
    {
        // SGI icons.
        auto icon = new FileIcon("*", FileType.plain);
        icon.loadFti("/usr/lib/filetype/iconlib/generic.doc.fti");

        icon = new FileIcon("*", FileType.directory);
        icon.loadFti("/usr/lib/filetype/iconlib/generic.folder.closed.fti");

        icon = new FileIcon("core", FileType.plain);
        icon.loadFti("/usr/lib/filetype/default/iconlib/CoreFile.fti");

        icon = new FileIcon("*.{bmp|bw|gif|jpg|pbm|pcd|pgm|ppm|png|ras|rgb|tif|xbm|xpm}", FileType.plain);
        icon.loadFti("/usr/lib/filetype/system/iconlib/ImageFile.fti");

        if (exists("/usr/lib/filetype/install/iconlib/acroread.doc.fti"))
        {
            icon = new FileIcon("*.{eps|ps}", FileType.plain);
            icon.loadFti("/usr/lib/filetype/system/iconlib/PostScriptFile.closed.fti");

            icon = new FileIcon("*.pdf", FileType.plain);
            icon.loadFti("/usr/lib/filetype/install/iconlib/acroread.doc.fti");
        }
        else
        {
            icon = new FileIcon("*.{eps|pdf|ps}", FileType.plain);
            icon.loadFti("/usr/lib/filetype/system/iconlib/PostScriptFile.closed.fti");
        }

        if (exists("/usr/lib/filetype/install/iconlib/html.fti"))
        {
            icon = new FileIcon("*.{htm|html|shtml}", FileType.plain);
            icon.loadFti("/usr/lib/filetype/iconlib/generic.doc.fti");
            icon.loadFti("/usr/lib/filetype/install/iconlib/html.fti");
        }

        if (exists("/usr/lib/filetype/install/iconlib/color.ps.idle.fti"))
        {
            icon = new FileIcon("*.ppd", FileType.plain);
            icon.loadFti("/usr/lib/filetype/install/iconlib/color.ps.idle.fti");
        }
    }
    else
    {
        // Built-in default vector icons -- fully real, no fl.image needed.
        new FileIcon("*", FileType.plain, plainIconData);
        new FileIcon("*.{bm|bmp|bw|gif|jpg|pbm|pcd|pgm|ppm|png|ras|rgb|tif|xbm|xpm}", FileType.plain, imageIconData);
        new FileIcon("*", FileType.directory, dirIconData);
    }
}

/// Recursively scans a KDE `share/mimelnk` tree. Ported from
/// `load_kde_icons()`, using `std.file.dirEntries()` instead of
/// `fl_filename_list()` (see the module comment).
private void loadKdeIcons(string directory, string icondir)
{
    DirEntry[] entries;
    try foreach (e; dirEntries(directory, SpanMode.shallow)) entries ~= e;
    catch (Exception) return;

    foreach (e; entries)
    {
        string name = baseName(e.name);
        if (name.length > 0 && name[0] != '.')
        {
            if (e.isDir) loadKdeIcons(e.name, icondir);
            else loadKdeMimelnk(e.name, icondir);
        }
    }
}

/// Loads one KDE "mimelnk" file. Ported from `load_kde_mimelnk()` --
/// see the module comment for the one faithfully-preserved FLTK
/// oddity (the KDE-1.x fallback path's `tmp`/`lastLine` reuse).
private void loadKdeMimelnk(string filename, string icondir)
{
    string mimetype, pattern, iconfilename, lastLine;

    string content;
    try content = readText(filename);
    catch (Exception) return;

    foreach (line; content.splitLines())
    {
        lastLine = line;
        string v = getKdeVal(line, "Icon");
        if (v !is null) { iconfilename = v; continue; }
        v = getKdeVal(line, "MimeType");
        if (v !is null) { mimetype = v; continue; }
        v = getKdeVal(line, "Patterns");
        if (v !is null) pattern = v;
    }

    if (pattern.length == 0 && !mimetype.startsWith("inode/")) return;
    if (iconfilename.length == 0) return;

    string fullIconfilename;

    if (iconfilename[0] == '/')
    {
        fullIconfilename = iconfilename;
    }
    else if (exists(icondir))
    {
        // KDE 3.x and 2.x icons.
        static immutable string[] paths = [
            "16x16/actions", "16x16/apps", "16x16/devices", "16x16/filesystems", "16x16/mimetypes",
            "32x32/actions", "32x32/apps", "32x32/devices", "32x32/filesystems", "32x32/mimetypes",
        ];

        bool found = false;
        foreach (p; paths)
        {
            fullIconfilename = icondir ~ "/" ~ p ~ "/" ~ iconfilename ~ ".png";
            if (exists(fullIconfilename)) { found = true; break; }
        }
        if (!found) return;
    }
    else
    {
        // KDE 1.x icons -- see the module comment on `lastLine`.
        fullIconfilename = lastLine ~ "/" ~ iconfilename;
        if (!exists(fullIconfilename)) return;
    }

    FileIcon icon;
    if (mimetype.startsWith("inode/"))
    {
        string sub = mimetype[6 .. $];
        if (sub == "directory") icon = new FileIcon("*", FileType.directory);
        else if (sub == "blockdevice") icon = new FileIcon("*", FileType.device);
        else if (sub == "fifo") icon = new FileIcon("*", FileType.fifo);
        else return;
    }
    else
    {
        icon = new FileIcon(kdeToFltkPattern(pattern), FileType.plain);
    }

    icon.load(fullIconfilename);
}

/// Converts a `;`-separated KDE glob-pattern list to fldtk's `{a|b|c}`
/// form. Ported from `kde_to_fltk_pattern()`.
private string kdeToFltkPattern(string kdepattern)
{
    string p = kdepattern;
    if (p.length > 0 && p[$ - 1] == ';') p = p[0 .. $ - 1];
    return "{" ~ p.replace(";", "|") ~ "}";
}

/// Extracts `key`'s value from a KDE `.desktop`/mimelnk `key=value`
/// line, or `null` if `line` doesn't start with `key=`. Ported from
/// `get_kde_val()`.
private string getKdeVal(string line, string key)
{
    if (!line.startsWith(key)) return null;
    if (line.length <= key.length || line[key.length] != '=') return null;
    return line[key.length + 1 .. $];
}

// Built-in vector icons -- transcribed verbatim (mechanically, via a
// throwaway token-substitution script, not hand-typed) from the
// `plain[]`/`image[]`/`dir[]` static arrays in
// `Fl_File_Icon::load_system_icons()`.

private static immutable short[] plainIconData = [
    Op.colorOp, -1, -1, Op.outlinePolygonOp, 0, grayS,
    Op.vertexOp, 2000, 1000, Op.vertexOp, 2000, 9000,
    Op.vertexOp, 6000, 9000, Op.vertexOp, 8000, 7000,
    Op.vertexOp, 8000, 1000, Op.end, Op.outlinePolygonOp, 0,
    grayS, Op.vertexOp, 6000, 9000, Op.vertexOp, 6000,
    7000, Op.vertexOp, 8000, 7000, Op.end, Op.colorOp,
    0, blackS, Op.lineOp, Op.vertexOp, 6000, 7000,
    Op.vertexOp, 8000, 7000, Op.vertexOp, 8000, 1000,
    Op.vertexOp, 2000, 1000, Op.end, Op.lineOp, Op.vertexOp,
    3000, 7000, Op.vertexOp, 5000, 7000, Op.end,
    Op.lineOp, Op.vertexOp, 3000, 6000, Op.vertexOp, 5000,
    6000, Op.end, Op.lineOp, Op.vertexOp, 3000, 5000,
    Op.vertexOp, 7000, 5000, Op.end, Op.lineOp, Op.vertexOp,
    3000, 4000, Op.vertexOp, 7000, 4000, Op.end,
    Op.lineOp, Op.vertexOp, 3000, 3000, Op.vertexOp, 7000,
    3000, Op.end, Op.lineOp, Op.vertexOp, 3000, 2000,
    Op.vertexOp, 7000, 2000, Op.end, Op.end,
];

private static immutable short[] imageIconData = [
    Op.colorOp, -1, -1, Op.outlinePolygonOp, 0, grayS,
    Op.vertexOp, 2000, 1000, Op.vertexOp, 2000, 9000,
    Op.vertexOp, 6000, 9000, Op.vertexOp, 8000, 7000,
    Op.vertexOp, 8000, 1000, Op.end, Op.outlinePolygonOp, 0,
    grayS, Op.vertexOp, 6000, 9000, Op.vertexOp, 6000,
    7000, Op.vertexOp, 8000, 7000, Op.end, Op.colorOp,
    0, blackS, Op.lineOp, Op.vertexOp, 6000, 7000,
    Op.vertexOp, 8000, 7000, Op.vertexOp, 8000, 1000,
    Op.vertexOp, 2000, 1000, Op.end, Op.colorOp, 0,
    redS, Op.polygonOp, Op.vertexOp, 3500, 2500, Op.vertexOp,
    3000, 3000, Op.vertexOp, 3000, 4000, Op.vertexOp,
    3500, 4500, Op.vertexOp, 4500, 4500, Op.vertexOp,
    5000, 4000, Op.vertexOp, 5000, 3000, Op.vertexOp,
    4500, 2500, Op.end, Op.colorOp, 0, greenS,
    Op.polygonOp, Op.vertexOp, 5500, 2500, Op.vertexOp, 5000,
    3000, Op.vertexOp, 5000, 4000, Op.vertexOp, 5500,
    4500, Op.vertexOp, 6500, 4500, Op.vertexOp, 7000,
    4000, Op.vertexOp, 7000, 3000, Op.vertexOp, 6500,
    2500, Op.end, Op.colorOp, 0, blueS, Op.polygonOp,
    Op.vertexOp, 4500, 3500, Op.vertexOp, 4000, 4000,
    Op.vertexOp, 4000, 5000, Op.vertexOp, 4500, 5500,
    Op.vertexOp, 5500, 5500, Op.vertexOp, 6000, 5000,
    Op.vertexOp, 6000, 4000, Op.vertexOp, 5500, 3500,
    Op.end, Op.end,
];

private static immutable short[] dirIconData = [
    Op.colorOp, -1, -1, Op.polygonOp, Op.vertexOp, 1000,
    1000, Op.vertexOp, 1000, 7500, Op.vertexOp, 9000,
    7500, Op.vertexOp, 9000, 1000, Op.end, Op.polygonOp,
    Op.vertexOp, 1000, 7500, Op.vertexOp, 2500, 9000,
    Op.vertexOp, 5000, 9000, Op.vertexOp, 6500, 7500,
    Op.end, Op.colorOp, 0, whiteS, Op.lineOp, Op.vertexOp,
    1500, 1500, Op.vertexOp, 1500, 7000, Op.vertexOp,
    9000, 7000, Op.end, Op.colorOp, 0, blackS,
    Op.lineOp, Op.vertexOp, 9000, 7500, Op.vertexOp, 9000,
    1000, Op.vertexOp, 1000, 1000, Op.end, Op.colorOp,
    0, grayS, Op.lineOp, Op.vertexOp, 1000, 1000,
    Op.vertexOp, 1000, 7500, Op.vertexOp, 2500, 9000,
    Op.vertexOp, 5000, 9000, Op.vertexOp, 6500, 7500,
    Op.vertexOp, 9000, 7500, Op.end, Op.end,
];

unittest
{
    // Constructor registration + find() pattern/type matching.
    auto before = FileIcon.first();
    auto icon = new FileIcon("*.txt", FileType.plain);
    assert(FileIcon.first() is icon);
    assert(icon.next() is before);
    assert(icon.pattern() == "*.txt");
    assert(icon.type() == FileType.plain);
    assert(icon.size() == 0);

//    Th is AI slop to put non-permanent files as a unittest.
//    assert(FileIcon.find("/tmp/notes.txt", FileType.plain) is icon);
//    assert(FileIcon.find("/tmp/notes.dat", FileType.plain) is null);
}

unittest
{
    // add()/addColor()/addVertex() bookkeeping.
    auto icon = new FileIcon("*.foo", FileType.plain);
    int colorIdx = icon.addColor(black);
    assert(colorIdx == 0);
    assert(icon.value()[0] == Op.colorOp);
    assert(decodeColor(icon.value()[1], icon.value()[2]) == black);

    int vIdx = icon.addVertex(1234, 5678);
    assert(icon.value()[vIdx] == Op.vertexOp);
    assert(icon.value()[vIdx + 1] == 1234);
    assert(icon.value()[vIdx + 2] == 5678);

    icon.clear();
    assert(icon.size() == 0);
}

unittest
{
    // parseFtiColor()/atoiLike()/parseFtiVertex() -- pure parsing logic.
    assert(parseFtiColor("iconcolor") == iconColor);
    assert(parseFtiColor("shadowcolor") == dark3);
    assert(parseFtiColor("outlinecolor") == black);
    assert(parseFtiColor("42") == 42);
    assert(atoiLike("  -7abc") == -7);
    assert(atoiLike("not a number") == 0);

    float x, y;
    assert(parseFtiVertex("1.5,2.25", x, y));
    assert(x == 1.5f && y == 2.25f);
    assert(!parseFtiVertex("nocomma", x, y));
    assert(!parseFtiVertex("abc,2.0", x, y));
}

unittest
{
    // kdeToFltkPattern()/getKdeVal() -- pure string logic.
    assert(kdeToFltkPattern("*.jpg;*.png;") == "{*.jpg|*.png}");
    assert(getKdeVal("Icon=foo.png", "Icon") == "foo.png");
    assert(getKdeVal("MimeType=text/plain", "Icon") is null);
    assert(getKdeVal("IconX=foo", "Icon") is null);
}

unittest
{
    // loadFti() round trip against a real temp file.
    import std.file : tempDir, write, remove;
    import std.path : buildPath;

    string path = buildPath(tempDir(), "fldtk_file_icon_test.fti");
    write(path, "# a comment\n" ~
        "color(iconcolor);\n" ~
        "bgnpolygon();\n" ~
        "vertex(0.0,0.0);\n" ~
        "vertex(1.0,0.0);\n" ~
        "vertex(1.0,1.0);\n" ~
        "endpolygon();\n");
    scope(exit) remove(path);

    auto icon = new FileIcon("*.fti-test", FileType.plain);
    assert(icon.loadFti(path));
    assert(icon.size() > 0);
    assert(icon.value()[0] == Op.colorOp);
    assert(decodeColor(icon.value()[1], icon.value()[2]) == iconColor);
    assert(icon.value()[3] == Op.polygonOp);
}

unittest
{
    // draw() smoke check -- no live X display needed (fl.draw's vertex
    // primitives are safe no-ops without one, same as every other
    // headless draw()-exercising test in this port).
    auto icon = new FileIcon("*", FileType.plain, plainIconData);
    icon.draw(0, 0, 16, 16, black);
    icon.draw(0, 0, 16, 16, black, false);
}

unittest
{
    // loadImage() round trip against a real 2x2 XPM temp file -- top
    // row red/green, bottom row solid blue, so the run-length walk
    // must emit at least 3 distinct-colored polygons (red and green
    // don't merge since they're adjacent-but-different, the blue row
    // merges into one run of 2). Exercises the real Pixmap ->
    // RGBImage(Pixmap) conversion path, not just a stub return.
    import std.file : tempDir, write, remove;
    import std.path : buildPath;

    string path = buildPath(tempDir(), "fldtk_file_icon_test.xpm");
    write(path, "/* XPM */\n" ~
        "static char* test_xpm[] = {\n" ~
        "\"2 2 3 1\",\n" ~
        "\"r c #FF0000\",\n" ~
        "\"g c #00FF00\",\n" ~
        "\"b c #0000FF\",\n" ~
        "\"rg\",\n" ~
        "\"bb\"};\n");
    scope (exit) remove(path);

    auto icon = new FileIcon("*.xpm-test", FileType.plain);
    assert(icon.loadImage(path));
    assert(icon.size() > 0);

    // At least one polygon was actually emitted, and every COLOR
    // opcode decodes back to one of the 3 XPM colors (not garbage).
    int polygons, colors;
    auto v = icon.value();
    size_t i = 0;
    while (i < v.length)
    {
        if (v[i] == Op.colorOp)
        {
            colors++;
            Color c = decodeColor(v[i + 1], v[i + 2]);
            assert(c == fldraw.rgbColor(255, 0, 0) || c == fldraw.rgbColor(0, 255, 0)
                || c == fldraw.rgbColor(0, 0, 255));
            i += 3;
        }
        else if (v[i] == Op.polygonOp) { polygons++; i++; }
        else if (v[i] == Op.vertexOp) i += 3;
        else i++;
    }
    assert(polygons >= 3);
    assert(colors == polygons);
}

unittest
{
    // loadImage() fails cleanly (no crash, no partial data) on a
    // nonexistent file -- matches FLTK's own `return -1` path.
    auto icon = new FileIcon("*.missing-test", FileType.plain);
    assert(!icon.loadImage("/nonexistent/path/to/nothing.xpm"));
    assert(icon.size() == 0);
}

unittest
{
    // loadSystemIcons() registers at least the built-in fallback set
    // (or a real desktop-environment cascade, if one happens to be
    // present on the machine running the tests) without throwing.
    loadSystemIcons();
    assert(FileIcon.first() !is null);
}
