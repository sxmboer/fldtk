/*
 * Port of `src/drivers/GDI/Fl_GDI_Graphics_Driver*.cxx` (FLTK 1.5.0,
 * ~/Repositories/fltk): the base class plus `_rect.cxx`/`_color.cxx`/
 * `_arci.cxx`/`_line_style.cxx`/`_vertex.cxx`. See `fl.platform_win32`'s
 * own module comment for the window/event-loop half this pairs with,
 * and `fl.graphics_driver`'s doc comment for the dispatch model
 * (`fl.draw`'s leaf primitives call `fl.graphics_driver.currentDriver`'s
 * methods instead of raw Xlib/Xft when one is active -- on Windows,
 * this driver is that `currentDriver`, set once by `fl.platform_win32`
 * at display-open time).
 *
 * **Scope**: implements exactly `fl.graphics_driver.GraphicsDriver`'s own
 * abstract method set, same self-imposed limit `fl.gl_graphics_driver`/
 * `fl.svg_file_surface` already follow -- not FLTK's full
 * `Fl_GDI_Graphics_Driver` surface (image caching, the full 60-method
 * `Fl_Scalable_Graphics_Driver` base FLTK layers this under).
 *
 * **Real coordinate scaling**: this port has no separate `Fl_Scalable_
 * Graphics_Driver`-equivalent decorator class (matching the same "fold
 * scaling directly into each primitive, no wrapper class" choice
 * `fl.draw`'s own `scaledFloor()` already makes on the X11 side -- see
 * that function's own doc comment), so
 * each coordinate-taking method here plays the role of *both* the
 * platform-independent scaling wrapper (`Fl_Scalable_Graphics_Driver::
 * rect()`/`rectf()`/`line()`/`xyline()`/`yxline()`, ported verbatim,
 * including `xyline()`/`yxline()`'s own pen-width-aware branch) and the
 * real GDI body (`_unscaled()`), reading `effectiveScale()` (this port's
 * existing live-drawing-scale `fl.core.currentScale()` model, matching
 * `fl.draw`'s own X11 primitives, refreshed from each window's own
 * screen at every `make_current()`-equivalent call site, rather than
 * FLTK's per-driver `Fl_WinAPI_Screen_Driver::scale_of_screen[]` lookup),
 * **except for a non-screen instance that opted out
 * via `useFixedScale()`**, see that method's own doc comment
 * (`fl.printer_win32.Printer`'s own dedicated driver instance needs a
 * neutral, DPI-independent `1.0` regardless of the screen's own scale
 * setting). `polygon()`/`arc()`/`pie()` are scaled here too
 * (`Fl_Scalable_Graphics_Driver::polygon()`/`arc()`/`pie()`, ported
 * verbatim). The vertex-path `end*()` family needs **no scaling of its
 * own** -- `fl.draw`'s own `vertex()`/`transformedVertex()` (via their
 * shared `appendVertexPoint()` choke point) already scale every point
 * *before* it ever reaches `currentDriver.endXxx()`, for every driver
 * uniformly (matching `fl.gl_graphics_driver`'s identical unscaled
 * `end*()` bodies) -- unlike `rect()`/`line()`/`polygon()`/`arc()`/
 * `pie()`, which `fl.draw` always dispatches at raw, unscaled
 * coordinates.
 *
 * **Real `Fl_XMap`/16-slot brush LRU cache**: a 256-entry `Xmap[]` table,
 * one per indexed `Fl_Color`, plus a single extra slot for "free"/
 * packed-RGB colors (matching FLTK's own split between
 * `Fl_GDI_Graphics_Driver::color(Fl_Color)`'s indexed-table lookup and
 * `color(uchar,uchar,uchar)`'s own single static slot), and the real
 * 16-slot brush LRU (`fl_brush_action()`) with its usage-count
 * eviction. See `color()`'s own doc comment for the exact port.
 *
 * **Coordinate-system quirks replicated faithfully, not "fixed"** (see
 * `Fl_GDI_Graphics_Driver_rect.cxx` itself): GDI's `LineTo()` excludes
 * its own destination pixel (unlike Xlib's inclusive `XDrawLine()`), and
 * `rect_unscaled()` carries FLTK's own documented "issue #1052" `+1`
 * fudge for `line_width<=1`. Both are ported as FLTK has them.
 *
 * **Real text**: `selectFont()`/`selectFontAngled()`/`fontFor()`/
 * `heightFor()`/`fontHeight()`/`fontDescent()`/`textWidth()`/
 * `codepointWidth()`/`textExtents()`/`computeTightExtents()` are a real
 * `Fl_GDI_Font_Descriptor`-equivalent font cache (`GdiFont`, keyed by
 * `(face, size, angle)`), and `fl.draw.d` has a real `version (Windows)`
 * branch for its own `fl_font()`/`height()`/`descent()`/`width()`/
 * `textExtents()` leaves calling into these methods. Ported in full,
 * including: the real per-codepoint width cache and multi-vs-single-
 * codepoint measurement split (`textWidth()`); real tight glyph-ink
 * `textExtents()` via `GetGlyphIndicesW()`/`GetGlyphOutlineW()`, with
 * FLTK's own `GetCharacterPlacementW()` fallback for surrogate-pair-
 * containing strings; rotated text (`draw(int angle, ...)`, a real
 * per-angle `CreateFontW()` escapement/orientation, matching FLTK's
 * `fl_angle_`-tracked cache key); and `nonspacing()`
 * (`fl.nonspacing`): `textWidth()`'s per-codepoint loop skips a
 * combining mark's own advance width exactly like FLTK's identical
 * check. Family/size/style mapping uses `fl.draw.getFont()`'s
 * already-style-char-prefixed raw name, resolved to real Windows family
 * names ("Microsoft Sans Serif"/"Courier New"/"Times New Roman"/etc,
 * see that function's own doc comment) rather than Xft's generic
 * Fontconfig aliases.
 */
module fl.gdi_graphics_driver;

version (Windows):

import core.sys.windows.windows;
import std.utf : toUTF16, toUTF16z;

import fl.graphics_driver : GraphicsDriver, Point;
import fl.enumerations : Color, Font, Fontsize, black;
import fl.core : currentScale;
import fl.nonspacing : nonspacing;

/// **Not `final`** (`fl.gdiplus_
/// graphics_driver.GdiPlusGraphicsDriver`) -- matches FLTK's own
/// real inheritance shape exactly: `Fl_GDIplus_Graphics_Driver : public
/// Fl_GDI_Graphics_Driver`, overriding only the antialiasing-relevant
/// subset (color/line/polygon/arc/pie/line-style/vertex-path) while
/// reusing everything else (text, images, clipping, rect/rectf/
/// xyline/yxline) from the base GDI implementation unchanged, same as
/// FLTK. `hdc_`/`lineWidth_`/`arcUnscaled()`/`pieUnscaled()` are
/// `protected` rather than `private` for exactly this reuse -- see
/// `GdiPlusGraphicsDriver`'s own doc comment for the full method-by-
/// method mapping.
class GdiGraphicsDriver : GraphicsDriver
{
    /// The device context every draw call below targets -- set by
    /// `fl.platform_win32` right before a window's `draw()` call (its
    /// own equivalent of `fl.draw.setDrawable()`; GDI has no ambient
    /// "current drawable" the way Xlib's `Display*`+`Drawable` pair
    /// gets threaded through `fl.draw`'s module state, since every
    /// `GraphicsDriver` method here takes no HDC parameter of its own).
    protected HDC hdc_;

    /// `-1` (the default) means "use the ambient `fl.core.currentScale()`",
    /// matching every on-screen instance of this driver. `fl.printer_
    /// win32.Printer` calls `useFixedScale(1.0)` on its own dedicated
    /// instance instead: a printer HDC's `MM_ANISOTROPIC` mapping already
    /// scales its own 720-logical-unit-per-10-inch coordinate space to
    /// the physical page independent of the *screen's* DPI setting, so
    /// additionally multiplying every coordinate by the screen's own
    /// scale factor (as every `effectiveScale()` call site below would
    /// otherwise do, via the live drawing scale `fl.core.currentScale()`)
    /// would print at the wrong size on any machine with display scaling
    /// enabled -- matching FLTK's own behavior, where a freshly
    /// constructed `Fl_GDI_Printer_Graphics_Driver` simply never has
    /// `Fl_Graphics_Driver::scale()` set away from its neutral `1.0`
    /// default the way an on-screen driver's DPI-aware setup does.
    private float scaleOverride_ = -1;

    /// See `scaleOverride_`'s own doc comment.
    void useFixedScale(float s) { scaleOverride_ = s; }

    /// Every coordinate-scaling call site below reads this instead of
    /// `fl.core.currentScale()` directly, so `scaleOverride_` can
    /// override it for a non-screen instance (see that field's own doc
    /// comment).
    private float effectiveScale() const
    {
        return scaleOverride_ >= 0 ? scaleOverride_ : currentScale();
    }

    /// Ported from `Fl_XMap` (`FL/win32.H`): one cached pen (plus, once a
    /// brush is requested for it, an index into `brushSlots_`) per real
    /// GDI color. `brush == -1` means "no cached brush slot yet",
    /// matching FLTK's own sentinel exactly.
    private struct Xmap
    {
        COLORREF rgb;
        HPEN pen;
        int brush = -1;
        int pwidth;
    }

    /// One slot per indexed `Fl_Color` (0-255) -- matches FLTK's own
    /// `Fl_XMap fl_xmap[256]`.
    private Xmap[256] xmapTable_;

    /// The single extra slot for "free"/packed-RGB colors (`Fl_Color`
    /// values with any of the low 8 bits' complement set, i.e. `c &
    /// 0xFFFFFF00`) -- matches FLTK's own `Fl_GDI_Graphics_Driver::
    /// color(uchar,uchar,uchar)`, which keeps its own single `static
    /// Fl_XMap xmap;` entirely separate from the 256-entry indexed table.
    private Xmap freeColorXmap_;

    /// Ported from the file-scope `Fl_XMap *fl_current_xmap` -- whichever
    /// of the 256 indexed slots or `freeColorXmap_` the most recent
    /// `color()` call touched. Read by `brushAction()` (`fl_brush()`'s
    /// equivalent) and `lineStyle()` (`fl_RGB()`'s equivalent).
    private Xmap* currentXmap_;

    /// Ported from `Fl_Graphics_Driver::line_width_` (the base-class
    /// field FLTK's own `color()`/`rect_unscaled()` both read) --
    /// this port has no such field on `GraphicsDriver` itself (no
    /// platform needed it before now), so it lives here instead, kept in
    /// sync by `lineStyle()`.
    protected int lineWidth_;

    /// One LRU-cached brush slot -- ported from `Fl_GDI_Graphics_Driver_
    /// color.cxx`'s own file-scope `struct Fl_Brush` inside
    /// `fl_brush_action()`.
    private struct BrushSlot
    {
        HBRUSH brush;
        ushort usage;
        Xmap* backref;
    }

    private enum brushSlotCount = 16; // FLTK's own FL_N_BRUSH
    private BrushSlot[brushSlotCount] brushSlots_;

    /// Called by `fl.platform_win32` right before this window's
    /// `draw()` runs (and cleared -- pass `null` -- once painting for
    /// this message finishes). Re-selects the already-cached pen into
    /// the new HDC rather than recreating it: a fresh `HDC` (a new
    /// `WM_PAINT`, or a different window) starts with nothing of ours
    /// selected into it, but the GDI object itself is still perfectly
    /// good and reusable across any DC. Brushes are always selected
    /// on-demand right before the specific fill call needing one
    /// (`brushAction()`, matching FLTK's own `fl_brush()` call
    /// sites), so there's nothing to re-select here for those.
    void setHdc(HDC hdc)
    {
        hdc_ = hdc;
        if (hdc_ is null) return;
        if (currentXmap_ !is null && currentXmap_.pen !is null) SelectObject(hdc_, currentXmap_.pen);
        if (currentFont_ !is null) SelectObject(hdc_, currentFont_.fid);
    }

    /// Ported from `Fl_Graphics_Driver::gc()` (the read half of FLTK's
    /// generic `void*`-typed `gc()`/`gc(void*)` accessor pair) -- narrowed
    /// to a concrete `HDC` return type, matching this port's existing
    /// preference for concrete types over `void*` casting elsewhere.
    /// Needed by `fl.draw.d`'s Windows offscreen-surface functions
    /// (`createOffscreen()`/`beginOffscreen()`/`copyOffscreen()`), the
    /// same way FLTK's own `Fl_GDI_Image_Surface_Driver`/
    /// `Fl_GDI_Graphics_Driver::copy_offscreen()` read `driver()->gc()`
    /// to find the DC a new offscreen bitmap or a blit should target.
    HDC hdc() const { return cast(HDC) hdc_; }

    /// One saved GDI "window origin" per nested `translateAll()` call,
    /// restored by the matching `untranslateAll()`. Ported from
    /// `Fl_GDI_Graphics_Driver::translate_all()`/`untranslate_all()`'s own
    /// `origins`/`depth` pair -- a growable D array instead of FLTK's
    /// fixed 10-deep `POINT[]` plus overflow warning, matching this
    /// port's usual "GC makes manual capacity management unnecessary"
    /// precedent (see `CLAUDE.md`) rather than replicating the fixed-size
    /// stack.
    private POINT[] originStack_;

    /// Shifts every subsequent drawing coordinate on this HDC by (-x,-y)
    /// FLTK units (scaled to device pixels), via GDI's own native
    /// `SetWindowOrgEx()` -- a single Win32 call that affects every GDI
    /// primitive already selected into `hdc_` uniformly, unlike this
    /// port's `fl.draw.pushTranslate()`/`popTranslate()` (which only
    /// affects the *native*, `currentDriver is null` drawing path -- see
    /// that function's own doc comment). Ported from `Fl_GDI_Graphics_
    /// Driver::translate_all(int, int)`. The one real caller: `fl.widget_
    /// surface.CopySurface`'s Windows `translate()`/`untranslate()`
    /// override, needed for the same reason the Linux side needs
    /// `pushTranslate()`/`popTranslate()` -- `WidgetSurface.draw(Widget)`'s
    /// own group-child traversal shifts the origin for each nested
    /// window/child it captures.
    void translateAll(int x, int y)
    {
        if (hdc_ is null) return;
        POINT origin;
        GetWindowOrgEx(hdc_, &origin);
        float s = effectiveScale();
        SetWindowOrgEx(hdc_, cast(int)(origin.x - x * s), cast(int)(origin.y - y * s), null);
        originStack_ ~= origin;
    }

    /// Undoes the most recent `translateAll()`. Ported from `Fl_GDI_
    /// Graphics_Driver::untranslate_all()`. A no-op if the stack is
    /// already empty (matches `fl.draw.popTranslate()`'s own underflow
    /// guard) or `hdc_` is null.
    void untranslateAll()
    {
        if (hdc_ is null || originStack_.length == 0) return;
        auto origin = originStack_[$ - 1];
        originStack_.length -= 1;
        SetWindowOrgEx(hdc_, origin.x, origin.y, null);
    }

    /// Ported from `Fl_GDI_Graphics_Driver::can_do_alpha_blending()`
    /// (`Fl_GDI_Graphics_Driver.cxx`) -- checked once, result cached
    /// (matching FLTK's own `static char been_here`/`can_do`
    /// pattern, here as ordinary function-local `static` state: a
    /// process-wide hardware/OS capability, not per-instance data, same
    /// intent either way). **Simplified from FLTK's own body**: no
    /// `LoadLibrary("MSIMG32.DLL")`/`GetProcAddress()` dance -- that
    /// exists FLTK purely to keep running on Windows 95 if
    /// `msimg32.dll` (added in Windows 2000) is missing entirely; this
    /// port already links `msimg32.lib` directly (`dub.sdl`), a
    /// deliberate call not to reproduce a 25+-year-obsolete compatibility
    /// path irrelevant to any target this port actually runs on, the
    /// same judgment already applied elsewhere in this codebase to
    /// legacy-OS branches. What FLTK's probe actually still matters
    /// for -- does *this* display/driver genuinely support the blend,
    /// not just "does the symbol exist" -- is kept: a real 1x1
    /// `AlphaBlend()` call, checked for success.
    private bool canDoAlphaBlending()
    {
        static bool checked, available;
        if (checked) return available;
        checked = true;

        HDC dc = GetDC(null);
        if (dc is null) return available;
        scope (exit) ReleaseDC(null, dc);

        HBITMAP bm = CreateCompatibleBitmap(dc, 1, 1);
        if (bm is null) return available;
        scope (exit) DeleteObject(bm);

        HDC testDc = CreateCompatibleDC(dc);
        if (testDc is null) return available;
        scope (exit) DeleteDC(testDc);

        auto old = SelectObject(testDc, bm);
        SetPixel(testDc, 0, 0, 0x01010101);

        BLENDFUNCTION bf;
        bf.BlendOp = AC_SRC_OVER;
        bf.SourceConstantAlpha = 255;
        bf.AlphaFormat = AC_SRC_ALPHA;
        available = AlphaBlend(dc, 0, 0, 1, 1, testDc, 0, 0, 1, 1, bf) != 0;
        SelectObject(testDc, old);
        return available;
    }

    // ---- Fl_GDI_Graphics_Driver_font.cxx ----
    //
    // Real font selection/metrics, backing `fl.draw.d`'s Windows leaves
    // (`fl_font()`, `height()`, `descent()`, `width()`, `textExtents()`)
    // -- kept here rather than in `fl.draw.d` itself, mirroring FLTK's
    // own structure (`Fl_GDI_Graphics_Driver` genuinely owns these
    // methods directly, unlike FLTK's Xft driver where they're free
    // functions -- see `fl.xft`'s own module comment for that contrast).

    /// `angle` joins `(face, size)` in the cache key -- ported from
    /// `find(Fl_Font, Fl_Fontsize, int angle)`'s own 3-part lookup
    /// (`Fl_GDI_Graphics_Driver_font.cxx`), needed once rotated text
    /// (`draw(int angle, ...)`) opens genuinely different `HFONT`s per
    /// angle.
    private struct FontKey
    {
        Font face;
        Fontsize size;
        int angle;
    }

    /// One cached, real GDI font -- ported from `Fl_GDI_Font_Descriptor`.
    /// `widthCache` replaces FLTK's own per-BMP-plane `width[64]`
    /// lookup-table-of-arrays (64 lazily-`malloc()`'d 1024-entry arrays)
    /// with a plain associative array -- a structural simplification
    /// only (FLTK's own paging scheme exists purely to avoid
    /// allocating a full 65536-entry array up front on 1990s-era
    /// hardware; a lazy AA has the identical *behavior*, just implemented
    /// natively rather than hand-rolled), not a behavioral one.
    private final class GdiFont
    {
        HFONT fid;
        int ascent, descent;
        int[wchar] widthCache;

        ~this()
        {
            if (fid !is null) DeleteObject(fid);
        }
    }

    private GdiFont[FontKey] fontCache_;
    private Font currentFontFace_ = -1;
    private Fontsize currentFontSize_ = 0;
    private int currentFontAngle_ = 0;
    private GdiFont currentFont_;

    /// `size * fl.core.currentScale()`, cast back to `Fontsize` -- matches
    /// FLTK's own `Fl_Scalable_Graphics_Driver::font()`: `font_
    /// unscaled(face, Fl_Fontsize(size * scale()));`. Every real `HFONT`
    /// this driver ever creates goes through this first (`fontFor()`'s
    /// only two callers, `selectFontAngled()`/`heightFor()`, both call
    /// this before touching `fontFor()`), so the glyphs GDI actually
    /// rasterizes are real device pixels, not raw FLTK units -- found
    /// missing entirely via a live user report at 150% scale: box/line
    /// primitives (already real `floorScaled()` users, see `rect()`/
    /// `rectf()` above) grew with the display, but every label stayed
    /// pinned at its native 100% pixel size, looking like it was "left
    /// behind." The matching other half of this fix -- dividing every
    /// *reported* metric (`heightFor()`, `fontHeight()`, `fontDescent()`,
    /// `textWidth()`, `textExtents()`) back down by the same factor
    /// before returning it -- is what keeps `fl.draw`'s own public API
    /// reporting FLTK units to its callers even though the real font
    /// underneath is now scaled, exactly matching `Fl_Scalable_Graphics_
    /// Driver::height()`/`descent()`/`width()`/`text_extents()`'s own
    /// `.../scale()` divisions.
    private Fontsize scaledFontSize(Fontsize size) const
    {
        return cast(Fontsize)(size * effectiveScale());
    }

    /// Invalidates every cached font for `fnum` -- called by
    /// `fl.draw.setFont()` when a font index is re-registered to a new
    /// name, matching FLTK's own cache-invalidating `d.font(-1, 0)`
    /// call at the end of `Fl::set_font()` (see `fl.xft`'s identical
    /// `fontCache_`-clearing logic in `fl.draw.setFont()` for the Linux
    /// counterpart this mirrors).
    void invalidateFontCache(Font fnum)
    {
        foreach (key; fontCache_.keys.dup)
            if (key.face == fnum) fontCache_.remove(key);
        if (currentFontFace_ == fnum) currentFontFace_ = -1;
    }

    /// Looks up (opening and caching, if new) the `GdiFont` for
    /// `(face, size, angle)`, **without** disturbing whatever font is
    /// currently selected for drawing -- the direct equivalent of
    /// `fl.xft.xftFontFor()`/FLTK's own `find()` helper
    /// (`Fl_GDI_Graphics_Driver_font.cxx`), used by `fl.draw.d`'s Windows
    /// `height(Font,Fontsize)` leaf to query an arbitrary font's metrics
    /// without changing what `fl_font()` last selected. `angle` defaults
    /// to `0` -- only `draw(int angle, ...)` ever asks for a rotated
    /// variant.
    private GdiFont fontFor(Font face, Fontsize size, int angle = 0)
    {
        auto key = FontKey(face, size, angle);
        if (auto p = key in fontCache_) return *p;

        import fl.draw : getFont;

        string raw = getFont(face);
        char c0 = raw.length > 0 ? raw[0] : ' ';
        bool recognized = c0 == ' ' || c0 == 'B' || c0 == 'I' || c0 == 'P';
        string family = (recognized && raw.length > 0) ? raw[1 .. $] : raw;
        bool bold = c0 == 'B' || c0 == 'P';
        bool italic = c0 == 'I' || c0 == 'P';

        // Ported from `Fl_GDI_Font_Descriptor`'s constructor: `angle*10`
        // for both escapement and orientation -- FLTK's own comment
        // notes both must be set together for a genuinely rotated
        // baseline (as opposed to just a rotated glyph in place).
        auto f = new GdiFont;
        f.fid = CreateFontW(-size, 0, angle * 10, angle * 10, bold ? FW_BOLD : FW_NORMAL, italic,
            FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            DEFAULT_QUALITY, DEFAULT_PITCH, family.toUTF16z);

        // A widget can legitimately call fl_font() (directly, or via
        // height()/width() during layout) before any window has been
        // shown -- `hdc_` is null then, matching fl.xft's own
        // xftFontFor() doc comment for the identical concern. A
        // temporary screen DC (GetDC(null)) is enough to query real
        // metrics without needing a live window; not cached (a widget
        // asking for metrics pre-show() is rare enough that a screen DC
        // per such call is not a meaningful cost), unlike FLTK's own
        // persistent fl_GetDC() cache.
        HDC measureDc = hdc_ !is null ? hdc_ : GetDC(null);
        SelectObject(measureDc, f.fid);
        TEXTMETRICW tm;
        GetTextMetricsW(measureDc, &tm);
        f.ascent = tm.tmAscent;
        f.descent = tm.tmDescent;
        if (hdc_ is null) ReleaseDC(null, measureDc);

        fontCache_[key] = f;
        return f;
    }

    /// Ported from `Fl_GDI_Graphics_Driver::font_unscaled()`/the file-
    /// scope `fl_font()` helper (`Fl_GDI_Graphics_Driver_font.cxx`) --
    /// makes `(face, size)` (always angle `0`; see `selectFontAngled()`
    /// for the rotated case `draw(int angle, ...)` uses) the active font
    /// for subsequent `draw()`/`fontHeight()`/`fontDescent()`/
    /// `textWidth()` calls, via `fontFor()` above.
    void selectFont(Font face, Fontsize size)
    {
        selectFontAngled(face, size, 0);
    }

    /// Ported from the file-scope `fl_font(Fl_Graphics_Driver*, Fl_Font,
    /// Fl_Fontsize, int angle)` helper, **minus its short-circuit
    /// entirely**: that short-circuit skips re-resolving the font when
    /// nothing looks like it changed, gated on `(face, size, angle)`
    /// plus a tracked `fl.core.currentScale()` snapshot -- but a scale
    /// change followed by a real drag sequence can leave that snapshot
    /// stale without the gate noticing, resolving the wrong font at the
    /// new scale. Every *other* coordinate-taking primitive in this
    /// class (`rect()`/`rectf()`/etc.) is unconditionally stateless --
    /// `floorScaled()` reads `fl.core.currentScale()` fresh on every
    /// single call, no "did this already happen" check of any kind --
    /// so the font path drops the optimization outright and matches
    /// that same unconditional shape: `fontFor()`'s own `FontKey`-keyed
    /// cache (a plain hash lookup, not a state machine) already makes a
    /// repeated resolution cheap, so there's no real cost to always
    /// resolving fresh -- only the *specific* remaining risk being
    /// eliminated is a stale `currentFont_` surviving past a scale
    /// change unnoticed.
    private void selectFontAngled(Font face, Fontsize size, int angle)
    {
        currentFontFace_ = face;
        currentFontSize_ = size;
        currentFontAngle_ = angle;
        currentFont_ = fontFor(face, scaledFontSize(size), angle);
        if (hdc_ !is null) SelectObject(hdc_, currentFont_.fid);
    }

    /// The height (ascent+descent, in pixels) of `(face, size)` --
    /// backs `fl.draw.d`'s Windows `height(Font,Fontsize)` leaf. Ported
    /// from `Fl_GDI_Graphics_Driver::height_unscaled()`, but taking an
    /// explicit `(face, size)` (via `fontFor()`, side-effect-free) rather
    /// than always reading the currently-*selected* font, matching
    /// `fl.xft.xftFontFor()`'s identical "without disturbing the current
    /// fl_font()" contract.
    int heightFor(Font face, Fontsize size)
    {
        auto f = fontFor(face, scaledFontSize(size));
        return cast(int)((f.ascent + f.descent) / effectiveScale());
    }

    int fontHeight() const
    {
        return currentFont_ !is null
            ? cast(int)((currentFont_.ascent + currentFont_.descent) / effectiveScale()) : -1;
    }

    int fontDescent() const
    {
        return currentFont_ !is null ? cast(int)(currentFont_.descent / effectiveScale()) : -1;
    }

    /// The width (in pixels) of `str[0 .. nChars]` in the current font --
    /// backs `fl.draw.d`'s Windows `width()` leaf. Ported from
    /// `Fl_GDI_Graphics_Driver::width_unscaled(const char*, int)` in
    /// full: a substring spanning more than one codepoint's own byte
    /// length gets one whole-string `GetTextExtentPoint32W()` call (real
    /// kerning); a call measuring at most one codepoint instead goes
    /// through the per-codepoint cached path (`codepointWidth()`),
    /// matching FLTK's own two-branch split exactly.
    double textWidth(const(char)[] str, int nChars)
    {
        import fl.text_buffer : utf8Len1, utf8DecodeAt;

        if (nChars <= 0) return 0.0;
        float s = effectiveScale();
        int len1 = str.length > 0 ? utf8Len1(str[0]) : 1;
        if (nChars > len1 && len1 > 0)
        {
            if (currentFont_ is null) return 0.0;
            wstring wstr = str[0 .. nChars].toUTF16;
            HDC measureDc = hdc_ !is null ? hdc_ : GetDC(null);
            SelectObject(measureDc, currentFont_.fid);
            SIZE sz;
            GetTextExtentPoint32W(measureDc, wstr.ptr, cast(int) wstr.length, &sz);
            if (hdc_ is null) ReleaseDC(null, measureDc);
            return cast(double) sz.cx / s;
        }

        if (currentFont_ is null) return -1.0;
        double w = 0.0;
        size_t i = 0;
        while (i < nChars)
        {
            int len;
            uint ucs = utf8DecodeAt(str, i, len);
            i += len;
            // `fl.nonspacing.nonspacing()`: FLTK skips combining
            // marks in exactly this loop (`if (!fl_nonspacing(ucs)) w +=
            // width_unscaled(ucs);`), since a combining
            // diacritic is rendered stacked onto the *previous* character
            // rather than occupying its own advance width. Only matters
            // for a single-codepoint measurement (this loop's own scope,
            // see this function's own doc comment) -- an entire label or
            // line takes the whole-string branch above instead, which
            // never touches this per-codepoint path at all.
            if (!nonspacing(ucs)) w += codepointWidth(ucs);
        }
        return w / s;
    }

    /// Ported from `width_unscaled(unsigned int)` -- the single-
    /// codepoint measurement `textWidth()` above calls once per
    /// codepoint. Real surrogate-pair handling for codepoints beyond the
    /// BMP (`ucs > 0xFFFF`, measured directly, uncached, matching
    /// FLTK's own "rarely used, simply measure explicitly" comment);
    /// BMP codepoints are cached per `GdiFont` (`widthCache`, keyed by
    /// UTF-16 code unit).
    private double codepointWidth(uint ucs)
    {
        if (currentFont_ is null) return 0.0;

        HDC measureDc = hdc_ !is null ? hdc_ : GetDC(null);
        scope (exit) if (hdc_ is null) ReleaseDC(null, measureDc);
        SelectObject(measureDc, currentFont_.fid);

        if (ucs > 0xFFFF)
        {
            uint v = ucs - 0x10000;
            wchar[2] u16 = [cast(wchar)(0xD800 + (v >> 10)), cast(wchar)(0xDC00 + (v & 0x3FF))];
            SIZE sz;
            GetTextExtentPoint32W(measureDc, u16.ptr, 2, &sz);
            return cast(double) sz.cx;
        }

        wchar wc = cast(wchar) ucs;
        if (auto p = wc in currentFont_.widthCache) return cast(double) *p;

        SIZE sz;
        GetTextExtentPoint32W(measureDc, &wc, 1, &sz);
        currentFont_.widthCache[wc] = sz.cx;
        return cast(double) sz.cx;
    }

    /// Returns the tight glyph-ink bounding box (dx, dy, w, h) of
    /// `str[0 .. nChars]`, relative to the pen position -- backs
    /// `fl.draw.d`'s Windows `textExtents()` leaf. Ported from
    /// `Fl_GDI_Graphics_Driver::text_extents_unscaled()` in full: the
    /// real `GetGlyphIndicesW()`/`GetGlyphOutlineW()` path for the common
    /// (no-surrogate-pairs) case, falling back to
    /// `GetCharacterPlacementW()` when the string contains UTF-16
    /// surrogate pairs (`GetGlyphIndicesW()` can only handle the BMP),
    /// and only falling back further to the width/height/descent-derived
    /// approximation (matching FLTK's own `exit_error:` label) if
    /// neither Windows API call actually succeeds.
    void textExtents(const(char)[] str, int nChars, out int dx, out int dy, out int w, out int h)
    {
        if (currentFont_ is null)
        {
            w = 0;
            h = 0;
            dx = dy = 0;
            return;
        }

        if (computeTightExtents(str, nChars, dx, dy, w, h))
        {
            // `computeTightExtents()` measures directly against the
            // real (now device-pixel-scaled, see `scaledFontSize()`)
            // `currentFont_.fid` -- divide back down to FLTK units here,
            // matching `Fl_Scalable_Graphics_Driver::text_extents()`'s
            // own unconditional `/scale()` on all four fields after
            // calling `text_extents_unscaled()`.
            float s = effectiveScale();
            dx = cast(int)(dx / s);
            dy = cast(int)(dy / s);
            w = cast(int)(w / s);
            h = cast(int)(h / s);
            return;
        }

        w = cast(int) textWidth(str, nChars);
        h = fontHeight();
        dx = 0;
        dy = fontDescent() - h;
    }

    private bool computeTightExtents(const(char)[] str, int nChars, out int dx, out int dy, out int w, out int h)
    {
        if (nChars <= 0) return false;
        wstring wstr = str[0 .. nChars].toUTF16;
        size_t len = wstr.length;
        if (len == 0) return false;

        HDC measureDc = hdc_ !is null ? hdc_ : GetDC(null);
        scope (exit) if (hdc_ is null) ReleaseDC(null, measureDc);
        SelectObject(measureDc, currentFont_.fid);

        bool hasSurrogates = false;
        foreach (wc; wstr)
            if (wc >= 0xD800 && wc < 0xE000) { hasSurrogates = true; break; }

        auto glyphs = new WORD[len];
        size_t glyphCount;

        if (hasSurrogates)
        {
            // GetGlyphIndicesW() can't handle surrogate pairs (BMP only)
            // -- GetCharacterPlacementW() is FLTK's own fallback,
            // real enough to also handle them.
            GCP_RESULTSW gcp;
            gcp.lpGlyphs = cast(LPWSTR) glyphs.ptr;
            gcp.nGlyphs = cast(UINT) len;
            gcp.lStructSize = GCP_RESULTSW.sizeof;
            DWORD dr = GetCharacterPlacementW(measureDc, wstr.ptr, cast(int) len, 0, &gcp, GCP_GLYPHSHAPE);
            if (dr == 0) return false;
            glyphCount = gcp.nGlyphs;
        }
        else
        {
            DWORD res = GetGlyphIndicesW(measureDc, wstr.ptr, cast(int) len, glyphs.ptr, GGI_MARK_NONEXISTING_GLYPHS);
            if (res == GDI_ERROR) return false;
            glyphCount = len;
        }

        static immutable MAT2 identity = MAT2(FIXED(0, 1), FIXED(0, 0), FIXED(0, 0), FIXED(0, 1));
        GLYPHMETRICS metrics;
        int maxw = 0, maxh = 0;
        int minx = 0, miny = -999_999;

        foreach (idx; 0 .. glyphCount)
        {
            DWORD r = GetGlyphOutlineW(measureDc, glyphs[idx], GGO_METRICS | GGO_GLYPH_INDEX,
                &metrics, 0, null, &identity);
            if (r == GDI_ERROR) return false;
            maxw += metrics.gmCellIncX;
            if (idx == 0) minx = metrics.gmptGlyphOrigin.x;
            int dh = metrics.gmBlackBoxY - metrics.gmptGlyphOrigin.y;
            if (dh > maxh) maxh = dh;
            if (miny < metrics.gmptGlyphOrigin.y) miny = metrics.gmptGlyphOrigin.y;
        }
        maxw = maxw - metrics.gmCellIncX + cast(int) metrics.gmBlackBoxX + metrics.gmptGlyphOrigin.x;
        w = maxw - minx;
        h = maxh + miny;
        dx = minx;
        dy = -miny;
        return true;
    }

    /// Ported from the file-scope `clear_xmap()`: deselects and deletes
    /// `xmap`'s pen (restoring whatever was selected before it, unless
    /// that happened to be the very pen being deleted), then resets its
    /// brush-slot index -- a stale index would otherwise point at a
    /// brush slot no longer backed by this color at all.
    private void clearXmap(ref Xmap xmap)
    {
        if (xmap.pen is null) return;
        HGDIOBJ oldPen = SelectObject(hdc_, GetStockObject(BLACK_PEN));
        if (oldPen != xmap.pen) SelectObject(hdc_, oldPen);
        DeleteObject(xmap.pen);
        xmap.pen = null;
        xmap.brush = -1;
    }

    /// Ported from the file-scope `set_xmap()`: (re)creates `xmap`'s pen
    /// at color `c`/width `lw`, deleting whatever pen it had before
    /// (same deselect-first dance as `clearXmap()`, inlined since
    /// FLTK's own `set_xmap()` duplicates it rather than calling
    /// `clear_xmap()`).
    private void setXmap(ref Xmap xmap, COLORREF c, int lw)
    {
        xmap.rgb = c;
        if (xmap.pen !is null)
        {
            HGDIOBJ oldPen = SelectObject(hdc_, GetStockObject(BLACK_PEN));
            if (oldPen != xmap.pen) SelectObject(hdc_, oldPen);
            DeleteObject(xmap.pen);
        }
        LOGBRUSH penbrush;
        penbrush.lbStyle = BS_SOLID;
        penbrush.lbColor = c;
        xmap.pen = ExtCreatePen(PS_GEOMETRIC | PS_ENDCAP_FLAT | PS_JOIN_ROUND, lw, &penbrush, 0, null);
        xmap.pwidth = lw;
        xmap.brush = -1;
    }

    // ---- Fl_GDI_Graphics_Driver_color.cxx ----

    /// Ported from `Fl_GDI_Graphics_Driver::color(Fl_Color)` and
    /// `color(uchar,uchar,uchar)` together (this port's single `Color`
    /// parameter already carries FLTK's own indexed-vs-"free" split
    /// in its high bits, matching the same check `fl.gl_graphics_driver.
    /// GdiGraphicsDriver.color()` already uses for the identical
    /// purpose): a packed/free RGB color goes through `freeColorXmap_`
    /// (FLTK's own single `static Fl_XMap` local to `color(uchar,
    /// uchar,uchar)`, entirely separate from the indexed table); an
    /// indexed color looks up `xmapTable_[c]` directly. Either way, the
    /// pen is only actually recreated when the cached RGB/width for that
    /// *specific* slot is stale -- repeated draws in the same color
    /// (the common case: box/border/text colors reused across many
    /// widgets in one frame) reuse the existing GDI pen object instead
    /// of recreating it on every single call.
    override void color(Color c)
    {
        import fl.draw : colorToRgb8;

        int tw = lineWidth_ ? lineWidth_ : cast(int) effectiveScale();
        if (tw == 0) tw = 1;

        if (c & 0xFFFFFF00)
        {
            ubyte r, g, b;
            colorToRgb8(c, r, g, b);
            COLORREF cr = RGB(r, g, b);
            if (freeColorXmap_.pen is null || cr != freeColorXmap_.rgb || tw != freeColorXmap_.pwidth)
            {
                clearXmap(freeColorXmap_);
                setXmap(freeColorXmap_, cr, tw);
            }
            currentXmap_ = &freeColorXmap_;
        }
        else
        {
            // `colorToRgb8()` must be recomputed and compared every
            // time, not just when `xmap.pen is null || xmap.pwidth !=
            // tw` (the pen's own existence/width) -- `Fl_Color` indices
            // in the "free" range (`FL_FREE_COLOR`..) exist specifically
            // to be reassigned at runtime (see `fl.core.setColor()`'s
            // own doc comment), so a pen already cached for index `c`
            // can go stale the moment `fl.core.setColor(c, r, g, b)`
            // changes what RGB that index resolves to. Matches the
            // packed-RGB branch just above exactly: always resolve the
            // live RGB and compare it, not just the pen's mere
            // existence/width.
            auto xmap = &xmapTable_[c & 0xff];
            ubyte r, g, b;
            colorToRgb8(c, r, g, b);
            COLORREF cr = RGB(r, g, b);
            if (xmap.pen is null || xmap.pwidth != tw || cr != xmap.rgb)
            {
                clearXmap(*xmap);
                setXmap(*xmap, cr, tw);
            }
            currentXmap_ = xmap;
        }
        SelectObject(hdc_, currentXmap_.pen);
    }

    /// Ported from `fl_brush()`/`fl_brush_action()`
    /// (`Fl_GDI_Graphics_Driver_color.cxx:129-189`) -- the real 16-slot
    /// brush LRU: a cache hit just bumps a usage counter (halving every
    /// slot's counter once any exceeds 32000, matching FLTK's own
    /// overflow-avoidance); a miss either claims a still-empty slot or
    /// evicts the least-recently-used one (deselecting/deleting its old
    /// `HBRUSH` and clearing the evicted color's own `Xmap.brush` index
    /// back to `-1` first). `reset` is `fl_brush_action(1)`'s own "tear
    /// everything down" mode, ported for completeness even though this
    /// port has no equivalent of FLTK's process-exit cleanup hook
    /// calling it yet. `package(fl)` (not `private`) since `fl.draw.
    /// drawCheck()`'s Windows body also needs a brush matching an
    /// arbitrary caller-supplied color, the same way `polygon()`/
    /// `rectf()` below already do from inside this class.
    package(fl) HBRUSH brushAction(bool reset)
    {
        if (reset)
        {
            SelectObject(hdc_, GetStockObject(BLACK_BRUSH));
            foreach (ref slot; brushSlots_)
            {
                if (slot.brush !is null) DeleteObject(slot.brush);
                slot.brush = null;
            }
            return null;
        }

        Xmap* xmap = currentXmap_;
        int i = xmap.brush;

        if (i != -1)
        {
            if (brushSlots_[i].brush !is null)
            {
                if (++brushSlots_[i].usage > 32000)
                {
                    foreach (ref slot; brushSlots_)
                        slot.usage = slot.usage > 16000 ? cast(ushort)(slot.usage - 16000) : 0;
                }
                return brushSlots_[i].brush;
            }
            // else: a stale index left over from a full reset() -- fall
            // through and (re)create at the same slot, matching
            // FLTK's own `if (brushes[i].brush == NULL) goto
            // CREATE_BRUSH;`.
        }
        else
        {
            int umin = 32000, imin = 0;
            bool foundEmpty = false;
            foreach (idx, ref slot; brushSlots_)
            {
                if (slot.brush is null)
                {
                    i = cast(int) idx;
                    foundEmpty = true;
                    break;
                }
                if (slot.usage < umin)
                {
                    umin = slot.usage;
                    imin = cast(int) idx;
                }
            }
            if (!foundEmpty)
            {
                i = imin;
                HGDIOBJ oldBrush = SelectObject(hdc_, GetStockObject(BLACK_BRUSH));
                if (oldBrush != brushSlots_[i].brush) SelectObject(hdc_, oldBrush);
                DeleteObject(brushSlots_[i].brush);
                brushSlots_[i].brush = null;
                brushSlots_[i].backref.brush = -1;
            }
        }

        brushSlots_[i].brush = CreateSolidBrush(xmap.rgb);
        brushSlots_[i].usage = 0;
        brushSlots_[i].backref = xmap;
        xmap.brush = i;
        return brushSlots_[i].brush;
    }

    // ---- Fl_GDI_Graphics_Driver_rect.cxx, scaled ----
    //
    // `floorScaled()` is `Fl_Scalable_Graphics_Driver::floor(int, float)`
    // ported verbatim ("compute int(x*s) accurately in the presence of
    // rounding error"). Every method below is now a direct port of its
    // real FLTK *pair* -- the platform-independent `Fl_Scalable_
    // Graphics_Driver::xxx()` scaling wrapper, folded together with
    // `Fl_GDI_Graphics_Driver::xxx_unscaled()`'s own real GDI body, the
    // same "no separate decorator class" merge this module's own top
    // comment already establishes for `lineStyle()`/`color()`.

    private int floorScaled(int x)
    {
        float s = effectiveScale();
        if (s == 1) return x;
        import std.math : abs;

        int retval = cast(int)(abs(x) * s + 0.001f);
        return x >= 0 ? retval : -retval;
    }

    /// `FillRect()` needs a brush, not the pen -- no Xlib equivalent
    /// (`XFillRectangle()` just uses the GC's foreground pixel).
    override void rectf(int x, int y, int w, int h)
    {
        if (w <= 0 || h <= 0) return;
        int sx = floorScaled(x), sy = floorScaled(y);
        int sw = floorScaled(x + w) - sx, sh = floorScaled(y + h) - sy;
        RECT r = RECT(sx, sy, sx + sw, sy + sh);
        FillRect(hdc_, &r, brushAction(false));
    }

    /// Ported from `Fl_Scalable_Graphics_Driver::rect()` (the scaling
    /// wrapper) calling into `Fl_GDI_Graphics_Driver::rect_unscaled()`
    /// (the real GDI body) -- including the real "issue #1052" fix:
    /// a solid, 1px-or-thinner line gets the old destination-`+1` fudge
    /// (`LineTo()`'s own exclusive-endpoint semantics, unlike Xlib's
    /// inclusive `XDrawLine()`), but a solid line *wider* than 1px
    /// instead temporarily switches to a squared cap style around the
    /// whole rectangle stroke (`applyLineStyleUnscaled()`, restored
    /// immediately after) -- FLTK's own comment points at the same
    /// GDI issue #1052 for both branches, just two different fixes for
    /// two different pen widths.
    override void rect(int x, int y, int w, int h)
    {
        if (w <= 0 || h <= 0) return;
        float s = effectiveScale();
        int si = cast(int) s;
        int d = si / 2;
        int ux = floorScaled(x) + d;
        int uy = floorScaled(y) + d;
        int uw = floorScaled(x + w) - floorScaled(x) - si;
        int uh = floorScaled(y + h) - floorScaled(y) - si;

        if (isSolid_ && lineWidth_ > 1)
            applyLineStyleUnscaled(lineStyleRaw_ | 0x300 /* capSquare */, lineWidth_, null);

        MoveToEx(hdc_, ux, uy, null);
        LineTo(hdc_, ux + uw, uy);
        if (isSolid_ && lineWidth_ <= 1) LineTo(hdc_, ux + uw, uy + uh + 1);
        LineTo(hdc_, ux + uw, uy + uh);
        LineTo(hdc_, ux, uy + uh);
        LineTo(hdc_, ux, uy);

        if (isSolid_ && lineWidth_ > 1)
            applyLineStyleUnscaled(lineStyleRaw_, lineWidth_, null);
    }

    /// `LineTo()` excludes its own destination pixel (Xlib's
    /// `XDrawLine()` is inclusive of both endpoints) -- the manual
    /// `SetPixel()` afterward paints the true endpoint GDI itself
    /// skipped, matching `line_unscaled()` exactly. Ported from
    /// `Fl_Scalable_Graphics_Driver::line(x,y,x1,y1)`: an axis-aligned
    /// call is redirected to `xyline()`/`yxline()` (their own, different
    /// scaling formula), matching FLTK exactly rather than always
    /// taking this diagonal path.
    override void line(int x, int y, int x1, int y1)
    {
        if (y == y1) { xyline(x, y, x1); return; }
        if (x == x1) { yxline(x, y, y1); return; }
        int sx = floorScaled(x), sy = floorScaled(y);
        int sx1 = floorScaled(x1), sy1 = floorScaled(y1);
        MoveToEx(hdc_, sx, sy, null);
        LineTo(hdc_, sx1, sy1);
        SetPixel(hdc_, sx1, sy1, currentXmap_.rgb);
    }

    /// Ported from `Fl_Scalable_Graphics_Driver::xyline(x,y,x1)` in
    /// full, including its own pen-width-aware branch: at a non-integer
    /// scale, with the current line width at or under the (integer)
    /// scale factor, and not `FL_UNIFORM_WIDTH`-flagged, the line is
    /// drawn *thin* (as `xyline_unscaled()` would draw it, geometric pens
    /// notwithstanding) but explicitly re-centered/re-widened via a
    /// transient `applyLineStyleUnscaled()` pen-width override for
    /// exactly this one stroke -- FLTK's own way of keeping a
    /// nominally-1px horizontal/vertical rule visually centered on its
    /// true (fractional-device-pixel) logical position at a scale like
    /// 1.25/1.5, rather than snapping unpredictably to whichever device
    /// row `floorScaled(y)` alone would land on.
    override void xyline(int x, int y, int x1)
    {
        if (y < 0) return;
        float s = effectiveScale();
        int sInt = cast(int) s;
        int xx = x < x1 ? x : x1;
        int xx1 = x < x1 ? x1 : x;

        if (s != sInt && lineWidth_ <= sInt && (lineStyleRaw_ & 0x0100_0000 /* uniformWidth */) == 0)
        {
            int lwidth = floorScaled(y + 1) - floorScaled(y);
            bool needChange = lwidth != sInt && isSolid_;
            if (needChange) applyLineStyleUnscaled(lineStyleRaw_, lwidth, null);
            int yy = floorScaled(y) + cast(int)(lwidth / 2.0f);
            MoveToEx(hdc_, floorScaled(xx), yy, null);
            LineTo(hdc_, floorScaled(xx1 + 1), yy); // xyline_unscaled()'s own destination +1, already folded in
            if (needChange) applyLineStyleUnscaled(lineStyleRaw_, lineWidth_, null);
        }
        else
        {
            int yy = floorScaled(y);
            yy += lineWidth_ <= sInt ? cast(int)(s / 2.0f) : sInt / 2;
            MoveToEx(hdc_, floorScaled(xx), yy, null);
            LineTo(hdc_, floorScaled(xx1 + 1), yy);
        }
    }

    /// Ditto, for the destination y -- matching `Fl_Scalable_Graphics_
    /// Driver::yxline(x,y,y1)`/`yxline_unscaled()` exactly (the same
    /// pen-width-aware branch as `xyline()`, transposed).
    override void yxline(int x, int y, int y1)
    {
        if (x < 0) return;
        float s = effectiveScale();
        int sInt = cast(int) s;
        int yy = y < y1 ? y : y1;
        int yy1 = y < y1 ? y1 : y;

        if (s != sInt && lineWidth_ <= sInt && (lineStyleRaw_ & 0x0100_0000 /* uniformWidth */) == 0)
        {
            int lwidth = floorScaled(x + 1) - floorScaled(x);
            bool needChange = lwidth != sInt && isSolid_;
            if (needChange) applyLineStyleUnscaled(lineStyleRaw_, lwidth, null);
            int xx = floorScaled(x) + cast(int)(lwidth / 2.0f);
            MoveToEx(hdc_, xx, floorScaled(yy), null);
            LineTo(hdc_, xx, floorScaled(yy1 + 1));
            if (needChange) applyLineStyleUnscaled(lineStyleRaw_, lineWidth_, null);
        }
        else
        {
            int xx = floorScaled(x);
            xx += lineWidth_ <= sInt ? cast(int)(s / 2.0f) : sInt / 2;
            MoveToEx(hdc_, xx, floorScaled(yy), null);
            LineTo(hdc_, xx, floorScaled(yy1 + 1));
        }
    }

    /// `Polygon()` fills with whatever brush is currently selected into
    /// the DC -- the explicit `SelectObject()` here matches
    /// `polygon_unscaled()` exactly (Xlib's `XFillPolygon()` needs no
    /// equivalent select step, it just uses the GC's foreground pixel).
    override void polygon(int x, int y, int x1, int y1, int x2, int y2)
    {
        POINT[3] pts = [
            POINT(floorScaled(x), floorScaled(y)),
            POINT(floorScaled(x1), floorScaled(y1)),
            POINT(floorScaled(x2), floorScaled(y2))
        ];
        SelectObject(hdc_, brushAction(false));
        Polygon(hdc_, pts.ptr, cast(int) pts.length);
    }

    override void polygon(int x, int y, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        POINT[4] pts = [
            POINT(floorScaled(x), floorScaled(y)),
            POINT(floorScaled(x1), floorScaled(y1)),
            POINT(floorScaled(x2), floorScaled(y2)),
            POINT(floorScaled(x3), floorScaled(y3))
        ];
        SelectObject(hdc_, brushAction(false));
        Polygon(hdc_, pts.ptr, cast(int) pts.length);
    }

    // ---- Fl_GDI_Graphics_Driver_line_style.cxx ----
    //
    // This method plays the role of *both* `Fl_Scalable_Graphics_
    // Driver::line_style()` (the platform-independent scale-computing
    // wrapper) and `Fl_GDI_Graphics_Driver::line_style_unscaled()` (the
    // real GDI body) together, since this port has no separate scaling-
    // decorator layer (`fl.graphics_driver`'s own established "fold
    // scaling directly in" precedent) -- ported from both, in their
    // real FLTK order. Reads the real, live `fl.core.currentScale()`
    // rather than hardcoding `1` -- it reduces to that exact behavior
    // when the scale is `1.0`.
    //
    // **A real, faithfully-ported FLTK quirk, not a bug**: unlike
    // `color()`, this method does *not* persist style/dash state for a
    // later `color()` call to reapply -- it directly overwrites whatever
    // pen `currentXmap_` (the *current* color) already has, immediately.
    // A subsequent `color()` call with a *different* color rebuilds a
    // plain solid pen with no memory of any dash pattern `lineStyle()`
    // set on the *previous* color -- matching FLTK's real, if
    // easy-to-miss, behavior exactly (real FLTK code almost always calls
    // `line_style()` *after* `color()` and resets it back to solid
    // afterward, which is why this ordering dependency rarely surfaces
    // as a visible bug in practice).
    /// Ported from the base class's own tracked fields (`Fl_Graphics_
    /// Driver::line_style_`, and GDI's own private `style_` -- both hold
    /// the same raw `style` value in FLTK too, just tracked in two
    /// places because of the base/derived split this port doesn't have;
    /// one field suffices here) plus `is_solid_`. Read by `rect()`'s own
    /// "issue #1052" CAP_SQUARE dance below.
    private int lineStyleRaw_;
    private bool isSolid_ = true;

    override void lineStyle(int style, int width, const(ubyte)[] dashes)
    {
        float scale = effectiveScale();

        // Fl_Scalable_Graphics_Driver::line_style()'s own scale step.
        int scaledWidth = width == 0
            ? (scale < 2 ? 0 : cast(int) scale)
            : cast(int)(width > 0 ? width * scale : -width * scale);
        lineWidth_ = scaledWidth;
        lineStyleRaw_ = style;
        isSolid_ = (style & 0xff) == 0 /* lineSolid */ && dashes.length == 0;

        uint[] dashArray;
        if (dashes.length && dashes[0] != 0)
        {
            dashArray.length = dashes.length > 16 ? 16 : dashes.length;
            foreach (i, ref d; dashArray) d = dashes[i];
        }
        int penWidth = scaledWidth;
        if ((style != 0 || dashArray.length != 0) && penWidth == 0) penWidth = cast(int) scale;

        applyLineStyleUnscaled(style, penWidth, dashArray);
    }

    /// Ported from `Fl_GDI_Graphics_Driver::line_style_unscaled()` --
    /// the real GDI body, taking an **already-scaled** `width` (matching
    /// FLTK's own `_unscaled` naming convention: no `currentScale()`
    /// read happens in here). Called both by the public `lineStyle()`
    /// above (the scaled entry point) and by `rect()`'s own temporary
    /// CAP_SQUARE switch, which must reuse the *current* (already-scaled)
    /// `lineWidth_` unchanged -- going through the public, scale-reading
    /// `lineStyle()` there would scale it a second time.
    private void applyLineStyleUnscaled(int style, int width, const(uint)[] dashes)
    {
        static immutable int[4] capTable = [PS_ENDCAP_FLAT, PS_ENDCAP_FLAT, PS_ENDCAP_ROUND, PS_ENDCAP_SQUARE];
        static immutable int[4] joinTable = [PS_JOIN_ROUND, PS_JOIN_MITER, PS_JOIN_ROUND, PS_JOIN_BEVEL];
        int s1 = PS_GEOMETRIC | capTable[(style >> 8) & 3] | joinTable[(style >> 12) & 3];

        uint[16] a;
        int n = 0;
        if (dashes.length)
        {
            s1 |= PS_USERSTYLE;
            foreach (d; dashes)
            {
                if (n >= 16) break;
                a[n++] = d;
            }
        }
        else
        {
            // FLTK's own lineSolid/lineDash/lineDot/lineDashDot/
            // lineDashDotDot values are deliberately chosen to already
            // equal GDI's own PS_SOLID/PS_DASH/PS_DOT/PS_DASHDOT/
            // PS_DASHDOTDOT constants (0-4) -- FLTK really does just
            // OR the raw low byte in directly, no translation table.
            s1 |= style & 0xff;
        }

        if (currentXmap_ is null) color(black);
        LOGBRUSH penbrush;
        penbrush.lbStyle = BS_SOLID;
        penbrush.lbColor = currentXmap_.rgb;
        HPEN newpen = ExtCreatePen(s1, width, &penbrush, n, n ? a.ptr : null);
        if (newpen is null) return;
        // `SelectObject(hdc_, newpen)`'s returned old pen must NOT also
        // be passed to `DeleteObject()`: `color()` always leaves
        // `currentXmap_.pen` selected into `hdc_` beforehand, so the
        // returned old pen *is* `currentXmap_.pen` in the normal case --
        // deleting it via both that return value and `currentXmap_.pen`
        // below would double-free the same HPEN handle, corrupting
        // whatever unrelated GDI object Windows had already reissued
        // that recycled handle value to. Matches the existing, already-
        // safe `setXmap()`/`clearXmap()` pattern just above: delete only
        // the cache's own retired pen, exactly once, and don't touch
        // whatever `SelectObject()` reports as previously selected (may
        // not even be a pen this driver owns, e.g. a stock object on a
        // freshly-acquired `hdc_`).
        SelectObject(hdc_, newpen);
        DeleteObject(currentXmap_.pen);
        currentXmap_.pen = newpen;
    }

    // ---- clipping -- HRGN + CombineRgn/SelectClipRgn, closer to
    // Xlib's own Region model than fl.draw's simpler rect-stack. See
    // GraphicsDriver.pushClip()'s own doc comment: this always receives
    // the already-intersected rectangle, so no intersection math is
    // needed here -- just remember what was selected before, so
    // popClip() can restore it.

    private HRGN[] savedClip_;

    override void pushClip(int x, int y, int w, int h)
    {
        HRGN saved = CreateRectRgn(0, 0, 0, 0);
        int had = GetClipRgn(hdc_, saved);
        savedClip_ ~= (had == 1) ? saved : null;
        if (had != 1) DeleteObject(saved);

        HRGN clip;
        if (scaleOverride_ >= 0)
        {
            // Printer (or any other non-screen) context: `useFixedScale()`
            // is only ever called for those (see its own doc comment),
            // and there, `MM_ANISOTROPIC` plus a possibly-active
            // `GM_ADVANCED` world transform (rotation) mean logical and
            // device units genuinely differ -- unlike the on-screen
            // `MM_TEXT` branch below, where they're 1:1 modulo this
            // port's own separate `effectiveScale()` multiplier.
            // `SelectClipRgn()`, unlike ordinary GDI drawing calls, takes
            // its region in DEVICE units and does *not* auto-convert via
            // the current mapping mode -- so passing it logical-space
            // coordinates directly (what `floorScaled()`'s plain
            // multiply amounts to once `useFixedScale(1.0)` makes it an
            // identity no-op) created a device-unit region sized as if
            // 1 point were 1 printer pixel, clipping everything down to
            // a tiny corner of the real, much-larger device canvas --
            // a real, user-reported bug (`device`'s "Printer" radio
            // button printing only a small fragment of the target
            // window). Ported from FLTK's own `Fl_GDI_Graphics_
            // Driver::XRectangleRegion()`, which takes this exact branch
            // whenever the current surface isn't the on-screen display:
            // map all 4 corners (not just 2, since a rotation may be
            // active) via `LPtoDP()` and build a polygon region from the
            // mapped points, instead of a rect region in raw,
            // wrong-unit coordinates.
            POINT[4] pt = [
                POINT(x, y), POINT(x + w, y), POINT(x + w, y + h), POINT(x, y + h)
            ];
            LPtoDP(hdc_, pt.ptr, 4);
            clip = CreatePolygonRgn(pt.ptr, 4, ALTERNATE);
        }
        else
        {
            // Missing entirely before -- every sibling primitive in this
            // class (`rect()`/`rectf()`/`line()`/etc.) scales via
            // `floorScaled()`, but this one took `fl.draw.pushClip()`'s raw
            // FLTK-unit rectangle straight into `CreateRectRgn()`. At any
            // scale != 1 the real on-screen clip region ended up far
            // smaller than the content actually being drawn into it,
            // clipping away part (or all) of anything drawn through it --
            // e.g. widget labels, which draw through a `pushClip()`'d
            // region during layout.
            int sx = floorScaled(x), sy = floorScaled(y);
            int sw = floorScaled(x + w) - sx, sh = floorScaled(y + h) - sy;
            clip = CreateRectRgn(sx, sy, sx + sw, sy + sh);
        }
        SelectClipRgn(hdc_, clip);
        DeleteObject(clip);
    }

    override void popClip()
    {
        if (savedClip_.length == 0) return;
        HRGN prev = savedClip_[$ - 1];
        savedClip_ = savedClip_[0 .. $ - 1];
        SelectClipRgn(hdc_, prev);
        if (prev !is null) DeleteObject(prev);
    }

    // ---- Fl_GDI_Graphics_Driver_arci.cxx ----
    // Ported verbatim, including the `w++/h++` (arc) vs. `x++/y++/w--/
    // h--` (pie) asymmetry and the near-zero-sweep SetPixel() special
    // case -- both are real, deliberate FLTK quirks, not
    // typos (see that file's own body for the reasoning: GDI's Arc()/
    // Pie() are unhappy with a start point equal to the end point).

    /// Ported from `Fl_Scalable_Graphics_Driver::arc()` (the scaling
    /// wrapper -- note its own real use of `lineWidth_` in the size
    /// computation, unlike `pie()`'s below) calling into
    /// `Fl_GDI_Graphics_Driver::arc_unscaled()`.
    override void arc(int x, int y, int w, int h, double a1, double a2)
    {
        float s = effectiveScale();
        int xx = floorScaled(x) + cast(int)((s - 1) / 2);
        int yy = floorScaled(y) + cast(int)((s - 1) / 2);
        int ww = floorScaled(x + w) - xx - 1 + lineWidth_ / 2 - cast(int)(s - 1);
        int hh = floorScaled(y + h) - yy - 1 + lineWidth_ / 2 - cast(int)(s - 1);
        arcUnscaled(xx, yy, ww, hh, a1, a2);
    }

    protected void arcUnscaled(int x, int y, int w, int h, double a1, double a2)
    {
        import std.math : cos, sin, PI;

        if (w <= 0 || h <= 0) return;
        w++; h++;
        int xa = cast(int)(x + w / 2 + cast(int)(w * cos(a1 / 180.0 * PI)));
        int ya = cast(int)(y + h / 2 - cast(int)(h * sin(a1 / 180.0 * PI)));
        int xb = cast(int)(x + w / 2 + cast(int)(w * cos(a2 / 180.0 * PI)));
        int yb = cast(int)(y + h / 2 - cast(int)(h * sin(a2 / 180.0 * PI)));
        if (xa == xb && ya == yb)
            SetPixel(hdc_, xa, ya, currentXmap_.rgb);
        else
        {
            int e = advancedModeEdge();
            Arc(hdc_, x, y, x + w - e, y + h - e, xa, ya, xb, yb);
        }
    }

    /// 1 when `hdc_` is in `GM_ADVANCED` (the printer's DC, set up for
    /// rotation), else 0. In that mode `Arc()`/`Pie()` include the right
    /// and bottom edges of their bounding rectangle, which
    /// `GM_COMPATIBLE` (the screen) excludes; FLTK's size adjustments
    /// above assume the latter. Subtracting this from the right/bottom
    /// keeps printed arcs meeting the straight edges drawn beside them
    /// (e.g. a round box's bottom line). A deviation from FLTK; see
    /// `FLTK_ISSUES.md`.
    private int advancedModeEdge()
    {
        return GetGraphicsMode(hdc_) == GM_ADVANCED ? 1 : 0;
    }

    /// Ported from `Fl_Scalable_Graphics_Driver::pie()` calling into
    /// `Fl_GDI_Graphics_Driver::pie_unscaled()`.
    override void pie(int x, int y, int w, int h, double a1, double a2)
    {
        int xx = floorScaled(x) - 1;
        int yy = floorScaled(y) - 1;
        int ww = floorScaled(x + w) - xx;
        int hh = floorScaled(y + h) - yy;
        pieUnscaled(xx, yy, ww, hh, a1, a2);
    }

    protected void pieUnscaled(int x, int y, int w, int h, double a1, double a2)
    {
        import std.math : cos, sin, PI;

        if (w <= 0 || h <= 0) return;
        if (a1 == a2) return;
        x++; y++; w--; h--;
        int xa = cast(int)(x + w / 2 + cast(int)(w * cos(a1 / 180.0 * PI)));
        int ya = cast(int)(y + h / 2 - cast(int)(h * sin(a1 / 180.0 * PI)));
        int xb = cast(int)(x + w / 2 + cast(int)(w * cos(a2 / 180.0 * PI)));
        int yb = cast(int)(y + h / 2 - cast(int)(h * sin(a2 / 180.0 * PI)));
        SelectObject(hdc_, brushAction(false));
        if (xa == xb && ya == yb)
        {
            MoveToEx(hdc_, x + w / 2, y + h / 2, null);
            LineTo(hdc_, xa, ya);
            SetPixel(hdc_, xa, ya, currentXmap_.rgb);
        }
        else
        {
            int e = advancedModeEdge();
            Pie(hdc_, x, y, x + w - e, y + h - e, xa, ya, xb, yb);
        }
    }

    // ---- Fl_GDI_Graphics_Driver_vertex.cxx's end_*() family, adapted
    // to this port's pre-accumulated Point[] dispatch model (same
    // adaptation fl.gl_graphics_driver already documents: by the time
    // any of these run, fl.draw has already applied the current
    // transform and closed any loop that needs closing -- see
    // fl.draw.endLoop()'s own doc comment, which appends the closing
    // point before calling here).

    override void endPoints(const(Point)[] pts)
    {
        foreach (p; pts) SetPixel(hdc_, p.x, p.y, currentXmap_.rgb);
    }

    override void endLine(const(Point)[] pts)
    {
        if (pts.length < 2)
        {
            endPoints(pts);
            return;
        }
        auto gdiPts = toPoints(pts);
        Polyline(hdc_, gdiPts.ptr, cast(int) gdiPts.length);
    }

    /// `fl.draw.endLoop()` has already appended the closing point --
    /// a plain `Polyline()` over the (already-closed) list matches
    /// FLTK's own `fixloop()` + `end_line()` pair exactly.
    override void endLoop(const(Point)[] pts)
    {
        endLine(pts);
    }

    override void endPolygon(const(Point)[] pts)
    {
        if (pts.length < 3)
        {
            endLine(pts);
            return;
        }
        auto gdiPts = toPoints(pts);
        SelectObject(hdc_, brushAction(false));
        Polygon(hdc_, gdiPts.ptr, cast(int) gdiPts.length);
    }

    /// Without sub-loop counts, the whole list is one `Polygon()`.
    /// `fl.draw` itself always calls `endComplexPolygonParts()` below.
    override void endComplexPolygon(const(Point)[] pts)
    {
        if (pts.length < 3)
        {
            endLine(pts);
            return;
        }
        auto gdiPts = toPoints(pts);
        SelectObject(hdc_, brushAction(false));
        Polygon(hdc_, gdiPts.ptr, cast(int) gdiPts.length);
    }

    /// Ported from `Fl_GDI_Graphics_Driver::end_complex_polygon()`: one
    /// `PolyPolygon()` over the sub-loops `fl_gap()` closed. `Polygon()`
    /// over the flat list would also outline the edges that join one
    /// sub-loop to the next -- stray lines across holes, visible in
    /// printed output (the GDI driver is the printer's driver).
    override void endComplexPolygonParts(const(Point)[] pts, const(int)[] counts)
    {
        if (pts.length < 3 || counts.length == 0)
        {
            endComplexPolygon(pts);
            return;
        }
        auto gdiPts = toPoints(pts);
        SelectObject(hdc_, brushAction(false));
        PolyPolygon(hdc_, gdiPts.ptr, counts.ptr, cast(int) counts.length);
    }

    private static POINT[] toPoints(const(Point)[] pts)
    {
        auto gdiPts = new POINT[pts.length];
        foreach (i, p; pts) gdiPts[i] = POINT(p.x, p.y);
        return gdiPts;
    }

    // ---- Fl_GDI_Graphics_Driver_font.cxx's draw_unscaled() ----

    /// Ported from `Fl_GDI_Graphics_Driver::draw_unscaled()`. Uses
    /// whichever real font `selectFont()` last resolved (falling back to
    /// the stock system font only if `fl_font()` was never called at
    /// all, matching FLTK's own `if (!font_descriptor())
    /// this->font(FL_HELVETICA, FL_NORMAL_SIZE);` guard).
    ///
    /// `x`/`y` are scaled via `floorScaled()` before reaching
    /// `TextOutW()`, matching every other coordinate-taking method in
    /// this driver (`rect()`/`line()`/`xyline()`/etc.), which plays the
    /// role of *both* FLTK's `Fl_Scalable_Graphics_Driver` scaling
    /// wrapper *and* the real GDI `_unscaled()` body (this module's own
    /// top comment). Checked directly against `Fl_Scalable_Graphics_
    /// Driver::draw()` (`Fl_Graphics_Driver.cxx:1005-1011`):
    /// `draw_unscaled(str, n, floor(x), floor(y + offset))`, where
    /// `floor(x)` is `floor(x, scale())` -- i.e. exactly this driver's
    /// own `floorScaled()`. `offset = (scale() == 1 ? 0 : -1)` is
    /// FLTK's own "issue #1308" baseline nudge, matching the
    /// Linux/Xft side of `fl.draw.fl_draw()`.
    override void draw(const(char)[] str, int nChars, int x, int y)
    {
        if (nChars <= 0) return;
        int offset = effectiveScale() == 1f ? 0 : -1;
        int sx = floorScaled(x);
        int sy = floorScaled(y + offset);
        wstring wstr = str[0 .. nChars].toUTF16;
        SelectObject(hdc_, currentFont_ !is null ? currentFont_.fid : GetStockObject(SYSTEM_FONT));
        SetTextColor(hdc_, currentXmap_.rgb);
        SetBkMode(hdc_, TRANSPARENT);
        SetTextAlign(hdc_, TA_BASELINE | TA_LEFT);
        TextOutW(hdc_, sx, sy, wstr.ptr, cast(int) wstr.length);
    }

    /// Ported from `Fl_GDI_Graphics_Driver::draw_unscaled(int angle,
    /// const char*, int, int, int)` -- temporarily reselects the current
    /// face/size at `angle` (`selectFontAngled()`, real `CreateFontW()`
    /// escapement/orientation), draws, then switches back to angle `0`
    /// for every subsequent unrotated call, matching FLTK's own
    /// trailing `fl_font(this, Fl_Graphics_Driver::font(), size_unscaled(),
    /// 0);`. Overrides `GraphicsDriver`'s own angle-ignoring default (see
    /// that class's doc comment) -- Windows joins the real drivers
    /// (SVG/PostScript) that actually rotate; this port's native X11/Xft
    /// on-screen path still doesn't (a separately documented gap, see
    /// `PORTING.md`'s `FL/Fl_Graphics_Driver.H` row).
    ///
    /// `x`/`y` are scaled the same way the non-angled overload above
    /// does -- checked against `Fl_Scalable_Graphics_Driver::draw(int
    /// angle, ...)` (`Fl_Graphics_Driver.cxx:1017-1022`):
    /// `draw_unscaled(angle, str, n, floor(x), floor(y))`, no `offset`
    /// nudge for the angled overload (that's specific to the non-angled
    /// "issue #1308" case FLTK too).
    override void draw(int angle, const(char)[] str, int nChars, int x, int y)
    {
        if (nChars <= 0) return;
        if (angle == 0)
        {
            draw(str, nChars, x, y);
            return;
        }

        selectFontAngled(currentFontFace_, currentFontSize_, angle);
        int sx = floorScaled(x);
        int sy = floorScaled(y);
        wstring wstr = str[0 .. nChars].toUTF16;
        SelectObject(hdc_, currentFont_ !is null ? currentFont_.fid : GetStockObject(SYSTEM_FONT));
        SetTextColor(hdc_, currentXmap_.rgb);
        SetBkMode(hdc_, TRANSPARENT);
        SetTextAlign(hdc_, TA_BASELINE | TA_LEFT);
        TextOutW(hdc_, sx, sy, wstr.ptr, cast(int) wstr.length);
        selectFontAngled(currentFontFace_, currentFontSize_, 0);
    }

    // ---- image/bitmap drawing ----
    //
    // Without an override here, `GraphicsDriver`'s own non-`abstract`
    // no-op defaults would silently swallow every call, so no
    // `Fl_RGB_Image`/`Fl_Pixmap`/`Fl_Bitmap` would ever paint anything
    // on Windows -- see `fl.draw.d`'s own `version (linux) {} else {}`
    // image-primitive split. Both are pure GDI (no GDI+/`msimg32.lib`
    // dependency, so this works identically whether `GdiGraphicsDriver`
    // or `GdiPlusGraphicsDriver` -- which doesn't override either -- is
    // the active driver).

    /**
     * Draws an 8-bit-per-channel image -- see `GraphicsDriver.drawImage()`'s
     * own doc comment for the exact `buf`/`d`/`l` contract (`d` = 1 gray,
     * 2 gray+alpha, 3 RGB, 4 RGBA; already pre-cropped/pre-resampled to
     * exactly `w`x`h`, no further scaling needed here).
     *
     * Real per-pixel alpha compositing: `d == 2`/`d == 4` (an alpha
     * channel present) blits via the real Win32 `AlphaBlend()`
     * (`msimg32.dll`) when `canDoAlphaBlending()` says it's available,
     * true-compositing against whatever's actually behind the image --
     * ported from `Fl_GDI_Graphics_Driver::draw_rgb()`'s own
     * `alpha_blend_()` call (`Fl_GDI_Graphics_Driver_image.cxx`),
     * ***not*** FLTK's own `cache()`-then-blend split (a persistent
     * per-`Fl_RGB_Image` offscreen-bitmap cache FLTK builds once and
     * reuses -- this port has no image-object cache at all anywhere,
     * matching `fl.draw.d`'s own already-established "no
     * offscreen-Pixmap image cache" scope decision on the Linux side, so
     * this rebuilds the premultiplied DIB fresh per call instead, same
     * as the *opaque* path just below always has).
     *
     * When `AlphaBlend()` genuinely isn't available, this falls back to
     * a real dithered transparency mask rather than a flat blend against
     * a fixed background color. This matters in practice on a real
     * printer HDC -- some printer drivers' own DDI doesn't implement
     * `AlphaBlend()` at all, and `canDoAlphaBlending()`'s own probe
     * (screen-only, one-time, cached for the whole process -- see its
     * own doc comment) can't detect that on its own; `drawImageAlphaBlended()`'s
     * real per-call `AlphaBlend()` return-value check (see that
     * function's own doc comment) is what actually catches a printer-
     * specific failure the coarse screen-based gate misses. Either way
     * this function ends up calling `drawImageDitheredMask()`, and
     * FLTK's own answer for exactly this case isn't "give up on
     * transparency" -- it's `Fl_GDI_Graphics_Driver::
     * create_alphamask()`'s 1-bit ordered-dither "screen door" mask
     * (ported verbatim, `ditherTable_` below), applied via the same
     * two-pass AND/OR masked blit `drawBitmap()` already uses in this
     * file, just with a real color bitmap selected for the OR pass
     * instead of a single flat `color()` -- see `drawImageDitheredMask()`'s
     * own doc comment. **Deliberately not where FLTK puts this
     * fallback**: real FLTK's version lives in `Fl_GDI_Graphics_Driver::
     * draw_fixed(Fl_RGB_Image*)`, reached (for a printer) only through a
     * dedicated `Fl_GDI_Printer_Graphics_Driver::draw_rgb()` world-
     * transform override -- but that override exists purely for
     * *scaling*; the masked-blit fallback itself was never printer-
     * specific in FLTK, it's the same shared base-class code path a
     * screen HDC can (rarely) hit too. This port has no separate
     * `Fl_GDI_Printer_Graphics_Driver`-equivalent subclass at all
     * (`fl.printer_win32`'s own module comment explains why -- text/
     * rects/lines/clipping don't need one), so the one piece of that
     * FLTK class actually worth porting -- this fallback -- belongs
     * directly here, in the shared driver every screen *and* printer
     * instance already uses, matching where FLTK's own mechanism
     * actually lives rather than inventing a subclass just to house it.
     */
    override void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        drawImageImpl(buf, x, y, w, h, d, l, true);
    }

    /// See `GraphicsDriver.drawImageFixed()`'s own doc comment for the
    /// double-scaling bug this override avoids: `buf` is already at its
    /// exact target device-pixel
    /// size (`drawW`x`drawH`), so only the *position* (`x`,`y`) still
    /// needs converting from FLTK units to device pixels -- `drawImageImpl()`'s
    /// `scaleDest = false` branch is exactly that: `floorScaled()` on
    /// `x`/`y` alone, `w`/`h` used exactly as given.
    override void drawImageFixed(const(ubyte)* buf, int drawW, int drawH, int drawL, int d, int x, int y)
    {
        drawImageImpl(buf, x, y, drawW, drawH, d, drawL, false);
    }

    /// Shared body for `drawImage()`/`drawImageFixed()` above --
    /// `scaleDest` selects which of the two contracts applies to `w`/`h`:
    /// `true` (`drawImage()`) means "FLTK-unit box, scale `floorScaled()`
    /// up/down to fit, same as every other primitive in this class";
    /// `false` (`drawImageFixed()`) means "already the final device-pixel
    /// size, use as given." Either way `(x,y)` (the destination position)
    /// is always converted via `floorScaled()` -- only the *size*
    /// half of the destination rect differs between the two contracts.
    private void drawImageImpl(const(ubyte)* buf, int x, int y, int w, int h, int d, int l, bool scaleDest)
    {
        if (buf is null || w <= 0 || h <= 0 || hdc_ is null) return;
        // A negative `d` is the documented horizontal-flip form (see
        // `fl.draw`'s `version (linux)` `drawImage()` doc comment, and
        // FLTK's own `fl_draw_image()`): the pixel pointer steps
        // left by `d`, each pixel's own bytes are still read forward,
        // and everything that sizes or classifies uses |d|. Only the
        // implicit row-stride default below takes |d| -- an explicitly
        // given negative `l` is the *vertical*-flip form and stays as
        // passed.
        immutable int ad = d < 0 ? -d : d;
        if (l == 0) l = w * ad;

        if (ad == 2 || ad == 4)
        {
            // canDoAlphaBlending() is a coarse, one-time, screen-only
            // gate; drawImageAlphaBlended()'s own return value is the
            // real, per-call check against *this* hdc_ (see its own doc
            // comment for why both matter -- a printer's own hdc_ can
            // fail even when the screen-based gate says yes).
            if (!canDoAlphaBlending() || !drawImageAlphaBlended(buf, x, y, w, h, d, l, scaleDest))
                drawImageDitheredMask(buf, x, y, w, h, d, l, scaleDest);
            return;
        }

        auto pixels = new uint[w * h];
        foreach (row; 0 .. h)
        {
            const(ubyte)* src = buf + row * l;
            size_t rowBase = cast(size_t) row * w;
            foreach (col; 0 .. w)
            {
                ubyte r, g, b;
                switch (ad)
                {
                case 1:
                    r = g = b = src[0];
                    break;
                case 2:
                {
                    uint a2 = src[1], a = 255 - a2;
                    r = g = b = cast(ubyte)((a2 * src[0] + 255 * a) / 255);
                    break;
                }
                case 3:
                    r = src[0]; g = src[1]; b = src[2];
                    break;
                default: // 4 (RGBA) -- also the fallback for any other d
                {
                    uint a2 = src[3], a = 255 - a2;
                    r = cast(ubyte)((a2 * src[0] + 255 * a) / 255);
                    g = cast(ubyte)((a2 * src[1] + 255 * a) / 255);
                    b = cast(ubyte)((a2 * src[2] + 255 * a) / 255);
                    break;
                }
                }
                pixels[rowBase + col] = (cast(uint) b) | (cast(uint) g << 8) | (cast(uint) r << 16);
                src += d;
            }
        }

        BITMAPINFO bmi;
        bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
        bmi.bmiHeader.biWidth = w;
        bmi.bmiHeader.biHeight = -h; // negative: top-down, matches pixels[] row order built above
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        // Scale the *destination* rect only when `scaleDest` says to --
        // `pixels[]` (the source, still at its native `w`x`h`) is
        // unaffected either way, `StretchDIBits()` already stretches
        // src->dst. Missing entirely before this whole function grew a
        // `scaleDest` parameter (same pattern as `drawBitmap()`'s own
        // fix): every other primitive in this class scales via
        // `floorScaled()`, but this one took `x,y,w,h` straight from its
        // caller, so any `Fl_RGB_Image`/`Fl_Pixmap`-drawn content stayed
        // pinned to its native pixel size at any scale != 1 instead of
        // growing with the display. The position half of that fix
        // (`floorScaled(x)`/`floorScaled(y)`) is unconditional -- only
        // the size half is skippable, for `drawImageFixed()`'s already-
        // device-pixel-sized `w`/`h` (see `drawImageFixed()`'s own doc
        // comment for why re-scaling *that* case double-scales instead).
        int dx = floorScaled(x), dy = floorScaled(y);
        int dw = scaleDest ? floorScaled(x + w) - dx : w;
        int dh = scaleDest ? floorScaled(y + h) - dy : h;
        StretchDIBits(hdc_, dx, dy, dw, dh, 0, 0, w, h, pixels.ptr, &bmi, DIB_RGB_COLORS, SRCCOPY);
    }

    /// Real per-pixel alpha compositing via `AlphaBlend()` -- see
    /// `drawImage()`'s own doc comment for why this exists as a
    /// separate function rather than a branch inside the loop above.
    /// Builds a *premultiplied* top-down 32bpp BGRA DIB (`AlphaBlend()`'s
    /// own `AC_SRC_ALPHA` mode requires each color channel already
    /// multiplied by its own alpha -- an undocumented-in-the-obvious-
    /// place but well-known Win32 requirement), wraps it in a real
    /// `HBITMAP` via `CreateDIBSection()` (unlike the plain
    /// `StretchDIBits()` path above, `AlphaBlend()` blits DC-to-DC, not
    /// memory-to-DC, so it needs a real source bitmap actually selected
    /// into a real DC, not just an in-memory buffer pointer), then
    /// blends it onto `hdc_`.
    ///
    /// **Returns whether the real `AlphaBlend()` call against `hdc_`
    /// itself actually succeeded**: `canDoAlphaBlending()`'s own probe
    /// only ever tests the *screen* DC, once, cached for the rest of the
    /// process -- it says nothing about whether `hdc_` itself (a real
    /// printer's own DC, in particular) actually supports it, and
    /// FLTK's own `fl_can_do_alpha_blending()` has the identical
    /// scope (a one-time screen-only probe, never re-tested per target).
    /// A printer whose DDI genuinely can't do real alpha compositing
    /// would otherwise hit this gap silently: the coarse screen-based
    /// probe says "yes," this function is called, the real per-call
    /// `AlphaBlend()` against the printer's own `hdc_` quietly fails,
    /// and nothing draws at all. Checking the real return value here and
    /// letting `drawImage()`'s caller fall back to
    /// `drawImageDitheredMask()` on `false` is what closes that gap --
    /// the coarse `canDoAlphaBlending()` check stays too, as a cheap
    /// first gate to skip this function's own DIB-building work entirely
    /// on a machine that can't do this at all.
    private bool drawImageAlphaBlended(const(ubyte)* buf, int x, int y, int w, int h, int d, int l, bool scaleDest)
    {
        auto pixels = new uint[w * h];
        foreach (row; 0 .. h)
        {
            const(ubyte)* src = buf + row * l;
            size_t rowBase = cast(size_t) row * w;
            foreach (col; 0 .. w)
            {
                ubyte r, g, b, a;
                if ((d < 0 ? -d : d) == 2) { a = src[1]; r = g = b = src[0]; }
                else { a = src[3]; r = src[0]; g = src[1]; b = src[2]; } // d == 4
                r = cast(ubyte)(r * a / 255);
                g = cast(ubyte)(g * a / 255);
                b = cast(ubyte)(b * a / 255);
                pixels[rowBase + col] = (cast(uint) a << 24) | (cast(uint) r << 16)
                    | (cast(uint) g << 8) | cast(uint) b;
                src += d;
            }
        }

        BITMAPINFO bmi;
        bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
        bmi.bmiHeader.biWidth = w;
        bmi.bmiHeader.biHeight = -h; // negative: top-down, matches pixels[] row order built above
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;

        void* dibBits;
        HBITMAP dib = CreateDIBSection(hdc_, &bmi, DIB_RGB_COLORS, &dibBits, null, 0);
        if (dib is null || dibBits is null) return false;

        import core.stdc.string : memcpy;
        memcpy(dibBits, pixels.ptr, pixels.length * uint.sizeof);

        HDC srcDc = CreateCompatibleDC(hdc_);
        if (srcDc is null) { DeleteObject(dib); return false; }
        auto oldBitmap = SelectObject(srcDc, dib);

        BLENDFUNCTION bf;
        bf.BlendOp = AC_SRC_OVER;
        bf.SourceConstantAlpha = 255;
        bf.AlphaFormat = AC_SRC_ALPHA;
        // Same destination-only scaling as drawImageImpl()'s own fix --
        // the source DIB (srcDc) stays at its native w x h, AlphaBlend()
        // stretches it into the destination rect (or not, per `scaleDest`
        // -- see drawImageImpl()'s own doc comment).
        int dx = floorScaled(x), dy = floorScaled(y);
        int dw = scaleDest ? floorScaled(x + w) - dx : w;
        int dh = scaleDest ? floorScaled(y + h) - dy : h;
        bool ok = AlphaBlend(hdc_, dx, dy, dw, dh, srcDc, 0, 0, w, h, bf) != 0;

        SelectObject(srcDc, oldBitmap);
        DeleteDC(srcDc);
        DeleteObject(dib);
        return ok;
    }

    /// The 16x16 ordered-dither threshold table `drawImageDitheredMask()`
    /// uses -- ported verbatim from `Fl_GDI_Graphics_Driver::
    /// create_alphamask()`'s own file-scope `dither[16][16]` (a "Simple
    /// 16x16 Floyd dither", FLTK's own comment). Indexed
    /// `[col & 15][row & 15]` (matching FLTK's own `dither[x & 15][y
    /// & 15]` exactly -- first index is the column, not the row).
    private static immutable ubyte[16][16] ditherTable_ = [
        [0,   128, 32,  160, 8,   136, 40,  168,
         2,   130, 34,  162, 10,  138, 42,  170],
        [192, 64,  224, 96,  200, 72,  232, 104,
         194, 66,  226, 98,  202, 74,  234, 106],
        [48,  176, 16,  144, 56,  184, 24,  152,
         50,  178, 18,  146, 58,  186, 26,  154],
        [240, 112, 208, 80,  248, 120, 216, 88,
         242, 114, 210, 82,  250, 122, 218, 90],
        [12,  140, 44,  172, 4,   132, 36,  164,
         14,  142, 46,  174, 6,   134, 38,  166],
        [204, 76,  236, 108, 196, 68,  228, 100,
         206, 78,  238, 110, 198, 70,  230, 102],
        [60,  188, 28,  156, 52,  180, 20,  148,
         62,  190, 30,  158, 54,  182, 22,  150],
        [252, 124, 220, 92,  244, 116, 212, 84,
         254, 126, 222, 94,  246, 118, 214, 86],
        [3,   131, 35,  163, 11,  139, 43,  171,
         1,   129, 33,  161, 9,   137, 41,  169],
        [195, 67,  227, 99,  203, 75,  235, 107,
         193, 65,  225, 97,  201, 73,  233, 105],
        [51,  179, 19,  147, 59,  187, 27,  155,
         49,  177, 17,  145, 57,  185, 25,  153],
        [243, 115, 211, 83,  251, 123, 219, 91,
         241, 113, 209, 81,  249, 121, 217, 89],
        [15,  143, 47,  175, 7,   135, 39,  167,
         13,  141, 45,  173, 5,   133, 37,  165],
        [207, 79,  239, 111, 199, 71,  231, 103,
         205, 77,  237, 109, 197, 69,  229, 101],
        [63,  191, 31,  159, 55,  183, 23,  151,
         61,  189, 29,  157, 53,  181, 21,  149],
        [254, 127, 223, 95,  247, 119, 215, 87,
         253, 125, 221, 93,  245, 117, 213, 85],
    ];

    /**
     * Fallback for `drawImage()`'s alpha-carrying case when real
     * `AlphaBlend()` compositing genuinely isn't available -- ported
     * from `Fl_GDI_Graphics_Driver::create_alphamask()` (the mask itself)
     * plus the masked-blit branch of `Fl_GDI_Graphics_Driver::draw_fixed
     * (Fl_RGB_Image*, ...)` (the technique that consumes it): a 1-bit
     * ordered-dither "screen door" transparency mask -- coarser than
     * true alpha compositing (each pixel ends up either fully opaque or
     * fully transparent, never blended), but real per-pixel transparency
     * instead of the flat, fully-opaque blend this used to fall back to.
     *
     * Builds two fresh GDI bitmaps per call (matching this port's own
     * "no persistent image-object cache" scope -- see `drawImageAlphaBlended()`'s
     * own doc comment): a full-color, alpha-ignoring DIB (`hbmColor`,
     * same per-pixel BGR packing `drawImage()`'s own plain opaque path
     * uses) and a monochrome dithered mask (`hbmMask`, GDI's own MSB-
     * first `CreateBitmap()` convention -- built LSB-first per byte, same
     * as `drawBitmap()`'s own mono-bitmap construction, then bit-reversed
     * via the shared `swapBitmapByte()` below). The two-pass blit
     * (`SRCAND` with the mask, then `SRCPAINT` with the color bitmap,
     * reusing one `HDC` for both selections) and its `TextColor`=white/
     * `BkColor`=black polarity for the `SRCAND` pass are the exact same
     * technique and reasoning as `drawBitmap()`'s own already-working
     * masked blit just below -- the only difference is the `SRCPAINT`
     * pass here selects a real color bitmap instead of relying on a
     * single flat `SetBkColor()` fill, since an RGB(A) image has a
     * different color at every pixel, not one uniform foreground color.
     */
    private void drawImageDitheredMask(const(ubyte)* buf, int x, int y, int w, int h, int d, int l, bool scaleDest)
    {
        immutable int ad = d < 0 ? -d : d;

        auto colorPixels = new uint[w * h];
        int monoStride = ((w + 15) / 16) * 2; // WORD-aligned, CreateBitmap()'s own requirement
        auto mono = new ubyte[monoStride * h];

        foreach (row; 0 .. h)
        {
            const(ubyte)* src = buf + row * l;
            size_t rowBase = cast(size_t) row * w;
            ubyte* monoRow = mono.ptr + row * monoStride;

            foreach (byteCol; 0 .. (w + 7) / 8)
            {
                ubyte maskByte = 0;
                foreach (bitIdx; 0 .. 8)
                {
                    int col = byteCol * 8 + bitIdx;
                    if (col >= w) break;
                    const(ubyte)* px = src + col * d;
                    ubyte r, g, b, a;
                    if (ad == 2) { a = px[1]; r = g = b = px[0]; }
                    else { a = px[3]; r = px[0]; g = px[1]; b = px[2]; } // ad == 4
                    // A transparent pixel stays black in the color
                    // bitmap, so the `SRCPAINT` pass leaves the
                    // destination it kept untouched.
                    if (a > ditherTable_[col & 15][row & 15])
                    {
                        maskByte |= cast(ubyte)(1 << bitIdx);
                        colorPixels[rowBase + col] = (cast(uint) b) | (cast(uint) g << 8) | (cast(uint) r << 16);
                    }
                }
                monoRow[byteCol] = swapBitmapByte(maskByte);
            }
        }

        HBITMAP hbmMask = CreateBitmap(w, h, 1, 1, mono.ptr);
        if (hbmMask is null) return;
        scope (exit) DeleteObject(hbmMask);

        BITMAPINFO bmi;
        bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
        bmi.bmiHeader.biWidth = w;
        bmi.bmiHeader.biHeight = -h; // negative: top-down, matches colorPixels[] row order built above
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32;
        bmi.bmiHeader.biCompression = BI_RGB;
        void* dibBits;
        HBITMAP hbmColor = CreateDIBSection(hdc_, &bmi, DIB_RGB_COLORS, &dibBits, null, 0);
        if (hbmColor is null) return;
        scope (exit) DeleteObject(hbmColor);
        import core.stdc.string : memcpy;
        memcpy(dibBits, colorPixels.ptr, colorPixels.length * uint.sizeof);

        HDC maskDc = CreateCompatibleDC(hdc_);
        if (maskDc is null) return;
        scope (exit) DeleteDC(maskDc);

        // Destination-only scaling, per `scaleDest` -- see
        // drawImageImpl()'s own doc comment.
        int dx = floorScaled(x), dy = floorScaled(y);
        int dw = scaleDest ? floorScaled(x + w) - dx : w;
        int dh = scaleDest ? floorScaled(y + h) - dy : h;

        int oldMode = SetStretchBltMode(hdc_, COLORONCOLOR);
        COLORREF oldText = GetTextColor(hdc_);
        COLORREF oldBk = GetBkColor(hdc_);

        auto oldSel = SelectObject(maskDc, hbmMask);
        SetTextColor(hdc_, RGB(255, 255, 255));
        SetBkColor(hdc_, RGB(0, 0, 0));
        StretchBlt(hdc_, dx, dy, dw, dh, maskDc, 0, 0, w, h, SRCAND);

        SelectObject(maskDc, hbmColor);
        StretchBlt(hdc_, dx, dy, dw, dh, maskDc, 0, 0, w, h, SRCPAINT);

        SelectObject(maskDc, oldSel);
        SetTextColor(hdc_, oldText);
        SetBkColor(hdc_, oldBk);
        SetStretchBltMode(hdc_, oldMode);
    }

    /// Bit-reverses a byte (MSB<->LSB) -- GDI's own monochrome-bitmap
    /// convention is MSB-leftmost, the opposite of this port's `Bitmap.
    /// array`/`Fl_Bitmap` LSB-leftmost convention (same requirement
    /// `fl.postscript.PostscriptGraphicsDriver.drawBitmap()`'s own
    /// `swapByte()` already documents for PostScript's identical MSB
    /// convention -- this is that same lookup-table technique, just not
    /// importable from here since the original is `private` to a
    /// different class).
    private static immutable ubyte[16] swappedNibble_ = [
        0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15
    ];
    private static ubyte swapBitmapByte(ubyte b)
    {
        return cast(ubyte)((swappedNibble_[b & 0xF] << 4) | swappedNibble_[b >> 4]);
    }

    /**
     * Draws a 1-bit stencil (the current `color()` showing through
     * "set" bits, fully transparent elsewhere) via the classic Win32
     * "AND-then-OR" 2-pass masked `StretchBlt()` technique -- no
     * `MaskBlt()`/`TransparentBlt()` needed (`msimg32.lib`-only), just
     * GDI's own documented mono-to-color "color expansion" rule (a
     * monochrome source bit 0 maps to the destination DC's current
     * `TextColor`, bit 1 to its `BkColor`, for *any* ROP that reads the
     * source): pass 1 (`SRCAND`) clears exactly the "set"-bit pixels to
     * black and leaves "clear"-bit pixels untouched (`TextColor` white
     * ANDs to a no-op, `BkColor` black ANDs to zero); pass 2
     * (`SRCPAINT`) ORs the real current color into those now-black
     * pixels and again leaves the others untouched (`TextColor` black
     * ORs to a no-op, `BkColor` set to the real color ORs zero up to
     * exactly that color). `bits` is repacked into a scratch buffer
     * matching GDI's own WORD-per-scanline `CreateBitmap()` alignment
     * requirement and bit-reversed via `swapBitmapByte()` along the way
     * -- see that function's own doc comment.
     *
     * `(cx,cy)` is honored here (a real sub-rectangle crop of `bits`
     * before scaling to `(w,h)`), unlike `PostscriptGraphicsDriver.
     * drawBitmap()`'s own faithfully-preserved FLTK quirk of
     * ignoring it -- `GraphicsDriver.drawBitmap()`'s own doc comment
     * explicitly leaves this to each concrete driver's discretion, and
     * honoring it is the more useful, expected behavior for an
     * interactive on-screen driver.
     */
    override void drawBitmap(const(ubyte)* bits, int dataW, int dataH, int x, int y, int w, int h, int cx, int cy)
    {
        if (bits is null || dataW <= 0 || dataH <= 0 || w <= 0 || h <= 0 || hdc_ is null) return;
        if (currentXmap_ is null) return;

        // Scale the destination rect the same way every other primitive
        // in this class does (rect()/rectf()'s own floorScaled() calls,
        // just above) -- without it, position drifts further off its
        // intended spot the farther x/y are from the window origin at
        // any scale other than 100% (visible as fl.adjuster.Adjuster's
        // arrow glyphs scattering away from their buttons).
        {
            int sx = floorScaled(x), sy = floorScaled(y);
            int sw = floorScaled(x + w) - sx, sh = floorScaled(y + h) - sy;
            x = sx; y = sy; w = sw; h = sh;
        }
        if (w <= 0 || h <= 0) return;

        // `cx`/`cy` arrive here in FLTK logical units (`fl.bitmap.
        // Bitmap.draw()`'s own `px`/`py`, clamped against this image's
        // *native* size) -- but `dataW`/`dataH` above are already the
        // *resampled*, device-pixel-resolution buffer size (`Bitmap.
        // draw()`'s own scale-aware recache), so `cx`/`cy` need
        // converting into that same space too, matching the real
        // Linux/Xlib body of `fl.draw.drawBitmapFixed()`: it scales its
        // own `cx`/`cy` via `scaledFloor()` before using them, for
        // exactly this reason (its own doc comment: "`dataW`/`dataH`...
        // are already the resampled bitmap's own real size" -- `cx`/`cy`
        // are not). Without that conversion, this override reads from
        // the wrong offset within the resampled buffer whenever a crop
        // (`cx`/`cy` != 0) is combined with a non-100%
        // scale.
        cx = floorScaled(cx);
        cy = floorScaled(cy);
        cx = cx < 0 ? 0 : (cx >= dataW ? dataW - 1 : cx);
        cy = cy < 0 ? 0 : (cy >= dataH ? dataH - 1 : cy);
        int srcW = dataW - cx;
        int srcH = dataH - cy;
        if (srcW <= 0 || srcH <= 0) return;

        int srcStride = (dataW + 7) / 8;
        int dstStride = ((srcW + 15) / 16) * 2; // WORD-aligned, CreateBitmap()'s own requirement

        auto mono = new ubyte[dstStride * srcH];
        foreach (row; 0 .. srcH)
        {
            const(ubyte)* srcRow = bits + (row + cy) * srcStride;
            ubyte* dstRow = mono.ptr + row * dstStride;
            foreach (col; 0 .. (srcW + 7) / 8)
            {
                // Each destination byte covers 8 *source* pixels
                // starting at bit `cx` within the original row --
                // reassembled bit by bit rather than a straight byte
                // copy, since `cx` isn't necessarily a multiple of 8.
                ubyte b = 0;
                foreach (bit; 0 .. 8)
                {
                    int srcCol = col * 8 + bit;
                    if (srcCol >= srcW) break;
                    int absCol = srcCol + cx;
                    bool set = ((srcRow[absCol / 8] >> (absCol % 8)) & 1) != 0;
                    if (set) b |= cast(ubyte)(1 << bit);
                }
                dstRow[col] = swapBitmapByte(b);
            }
        }

        HBITMAP hbmMask = CreateBitmap(srcW, srcH, 1, 1, mono.ptr);
        if (hbmMask is null) return;
        scope (exit) DeleteObject(hbmMask);

        HDC hdcMask = CreateCompatibleDC(hdc_);
        if (hdcMask is null) return;
        scope (exit) DeleteDC(hdcMask);
        HGDIOBJ oldBmp = SelectObject(hdcMask, hbmMask);
        scope (exit) SelectObject(hdcMask, oldBmp);

        int oldMode = SetStretchBltMode(hdc_, COLORONCOLOR);
        COLORREF oldText = GetTextColor(hdc_);
        COLORREF oldBk = GetBkColor(hdc_);

        SetTextColor(hdc_, RGB(255, 255, 255));
        SetBkColor(hdc_, RGB(0, 0, 0));
        StretchBlt(hdc_, x, y, w, h, hdcMask, 0, 0, srcW, srcH, SRCAND);

        SetTextColor(hdc_, RGB(0, 0, 0));
        SetBkColor(hdc_, currentXmap_.rgb);
        StretchBlt(hdc_, x, y, w, h, hdcMask, 0, 0, srcW, srcH, SRCPAINT);

        SetTextColor(hdc_, oldText);
        SetBkColor(hdc_, oldBk);
        SetStretchBltMode(hdc_, oldMode);
    }
}
