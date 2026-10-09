/*
 * Partial port of FL/fl_draw.H (FLTK 1.5.0) -- FLTK's whole
 * drawing-primitives API (lines, rects, text, clipping, images, ...).
 * Most entry points below still forward straight to Xlib/Xft, matching
 * `fl.platform_x11`'s own "no polymorphic hierarchy for a single
 * backend" precedent -- but that is not the whole story: a
 * deliberately minimal `fl.graphics_driver.GraphicsDriver` abstraction
 * also exists (`Fl_SVG_File_Surface`/
 * `Fl_PostScript_File_Device` are its second/third consumers, see
 * that module's own doc comment for the full, current method list),
 * and this module's actual *leaf* primitives -- the ones that call into
 * `fl.xlib`/`fl.xft` directly, as opposed to a pure composition of other
 * primitives -- check `fl.graphics_driver.currentDriver` first and
 * delegate to it when non-null, falling through to the existing direct
 * Xlib body only when it's null (the "native" case, unchanged from
 * before): `fl_color()`; the 4-arg `fl_rectf()`/`fl_rect()`; the 4-arg
 * `fl_line()`; the 3-arg `fl_xyline()`/`fl_yxline()`; both `fl_polygon()`
 * overloads; `lineStyle()`; `pushClip()`/`popClip()` (these two
 * always run their native bookkeeping regardless of dispatch, and
 * additionally notify the driver -- see their own doc comments, this is
 * the one "both, not either/or" case); the int-arg `fl_arc()`/`fl_pie()`;
 * the vertex-path `endPoints()`/`endLine()`/`endLoop()`/
 * `endPolygon()`/`endComplexPolygon()` family (their own
 * `fl_begin_*()`/`vertex()`/`fl_gap()` counterparts stay pure,
 * platform-independent bookkeeping with no dispatch of their own --
 * FLTK's own base `Fl_Graphics_Driver` keeps vertex accumulation
 * out of its subclasses' reach the same way); and the 3-arg positional
 * `fl_draw()` text leaf. Every other entry point in this file is a pure
 * composition of those leaves (e.g. the 5/6-arg `fl_rect()`/`fl_line()`/
 * `fl_xyline()`/`fl_yxline()` overloads, `point()`, `circle()`/
 * `fl_arc(double,...)` -- see `fl.graphics_driver.GraphicsDriver`'s own
 * doc comment for why those two need no driver method despite drawing
 * curves) and needs no dispatch check of its own -- it routes correctly
 * for free. Text metrics (`fl_font()`/`fl_size()`/`width()`/
 * `height()`/`descent()`/`fl_measure()`) are deliberately never
 * dispatched either, on purpose, not as a gap -- see `GraphicsDriver`'s
 * own doc comment. Despite the module's origin as a placeholder (each entry
 * point below was originally stubbed out purely so some already-ported
 * widget's draw() had a name to call, one widget at a time, as
 * documented in the bullet list right below), most of what's listed
 * here is real -- see the "REAL (Linux/X11) BODIES" paragraph
 * onward for the current, accurate picture of what actually draws
 * pixels. Images are real too: see `drawImage()`/
 * `drawImageMono()` below. `fl.image` has no remaining codec gap --
 * XBM/XPM/PNM/BMP/ICO/GIF/SVG/PNG/JPEG are all native decoders now.
 *
 *  - pushClip()/popClip()/notClipped(): added for fl.group's draw().
 *  - fl_color()/fl_pie()/inactive()/contrast()/colorAverage()/
 *    drawCheck()/drawRadio(): added for fl.light_button's
 *    draw() (src/Fl_Light_Button.cxx).
 *  - fl_line()/fl_yxline()/fl_xyline(): added for fl.slider's draw()
 *    (src/Fl_Slider.cxx). fl_darker()/fl_lighter() are also added here
 *    rather than fl.enumerations (where their FLTK inline
 *    definitions actually live, in Enumerations.H) purely to avoid a
 *    fl.enumerations <-> fl.draw circular import -- they're trivial
 *    colorAverage() wrappers either way.
 *  - fl_font()/fl_draw() (text)/fl_rectf(): added for fl.value_slider's
 *    draw() (src/Fl_Value_Slider.cxx) and fl.roller's draw()
 *    (src/Fl_Roller.cxx).
 *  - height()/descent()/width()/a 4-arg positional fl_draw()
 *    overload/clipBox(): added for fl.text_display's draw()/layout code
 *    (src/Fl_Text_Display.cxx), which measures and lays out text long
 *    before it draws a single pixel of it. height()/descent()/
 *    width() are real (see the "TEXT" paragraph below) --
 *    fl.text_display's layout math now runs against real glyph metrics
 *    instead of the "font size + 4"/6px-per-byte placeholders it
 *    originally shipped with (those placeholders matched FLTK's own
 *    documented `#define TMPFONTWIDTH 6 // CET - FIXME` stand-in, kept
 *    only as long as no real metrics existed). clipBox() is real
 *    too (see the "CLIPPING" paragraph below).
 *
 * REAL (Linux/X11) BODIES: fl_color()/fl_rectf()/fl_line()/fl_xyline()
 * (all 3 overloads)/fl_yxline() (all 3 overloads; the 4/5-arg forms
 * are pure compositions of the 3-arg Xlib body, added for
 * fl.return_button's returnArrow()), plus drawBoxAt() (backing
 * Widget.drawBox(), see fl.widget), draw real pixels via Xlib
 * (fl.xlib) rather than being no-ops -- see initGraphics()/
 * setDrawable()'s doc comments for how fl.platform_x11 wires this up,
 * and drawBoxAt()'s for which boxtypes are covered (the
 * section comments through this module cover each family, including
 * the "rounded" CSS-style family and all four scheme families --
 * gleam/gtk+/oxy/plastic).
 *
 * TEXT (Linux/X11): fl_font()/fl_draw() (both overloads)/width()/
 * height()/descent()/fl_measure() are real too, via a new
 * Xft binding (fl.xft) -- see the "Text drawing" section below
 * fl_font() for the font-name mapping and exactly what's simplified
 * relative to FLTK's fancier fl_draw() (no word-wrap, no `@`-symbol
 * glyphs, no image-adjacent layout, no shortcut underline). This is
 * what finally makes Widget.drawLabel() (fl.widget) draw real glyphs
 * for Box/Button/etc. labels, not just their box.
 *
 * COLOR MATH: colorAverage()/inactive()/contrast()/
 * rgbColor() are real too now (platform-independent -- pure
 * arithmetic on decoded RGB channels, no driver needed), which is what
 * makes every widget's existing `activeR() ? color() :
 * inactive(color())`-style calls (fl.dial/fl.clock/fl.counter/
 * fl.roller/fl.light_button/...) actually dim when disabled, and
 * fl.light_button's/fl.progress's/fl.text_display's contrast() calls
 * actually recolor for legibility, instead of being no-ops. Also fixed
 * as part of the same change: fl_color()'s and the Xft text color
 * path's Color-to-RGB decoding now handles "free" (packed-RGB) colors
 * -- like the ones colorAverage() produces -- not just indexed
 * ones (see colorToRgb8()'s doc comment); before this they'd have
 * silently rendered as black. contrast() defaults to FLTK's real
 * CIELAB perceptual-contrast algorithm, with a full
 * mode/level/custom-function subsystem for switching to the older
 * FLTK-1.3.x-compatible "legacy" algorithm or a caller-registered one --
 * see contrast()'s own doc comment.
 *
 * CLIPPING: pushClip()/popClip()/notClipped()/clipBox() are real
 * too, and -- unlike the color math above -- fully platform-
 * independent even for the bookkeeping/query side (only actually
 * restricting rendering is Linux-specific): see the "Clipping" section
 * comment above pushClip() for the ClipEntry[] rectangle-stack design
 * (deliberately simpler than FLTK's general Fl_Region, and exactly
 * as capable for every case this port exercises) and restoreClip()'s
 * doc comment for how a pushed clip reaches both the plain Xlib GC and
 * the separate Xft drawing handle. This is what makes fl.group's
 * clipChildren(), fl.pack's inter-child filler drawing, and
 * fl.progress's two-region (filled-vs-rest) split all actually confine
 * their drawing to the intended area now, instead of drawing across
 * their widget's full bounds every time.
 *
 * ELLIPSES/PIE SLICES/CHECKMARKS/RADIO DOTS: fl_arc()/fl_pie() (real
 * now, via XDrawArc/XFillArc -- see the section comment above them for
 * how FLTK's scale-transform wrapper collapses away at this port's
 * fixed scale of 1) and the new drawCircle() they back are what
 * make drawCheck()/drawRadio() real too (see their own doc
 * comments). This is what makes fl.light_button's checkbox/radio glyph
 * and fl.dial's fillDial mode render -- see
 * `smoke-tests/checkmarks.d`: a checked CheckButton/RoundButton and a
 * 70%-filled FillDial all render their real glyph, not a blank box.
 *
 * All four scheme boxtype families (gleam/gtk+/oxy/plastic) are real
 * too -- see the section comments above gtkColor()/gleamColor()/
 * oxyColor()/shadeColor() further down this module. Every boxtype
 * `fl.core.boxTable` has metrics for is drawable; `drawBoxAt()`'s
 * `default:` case is pure forward-compat, not a real gap.
 *
 * TRANSFORM STACK / VERTEX PATH: pushMatrix()/popMatrix()/
 * fl_translate()/fl_scale()/fl_rotate()/beginPolygon()/
 * endPolygon()/beginLoop()/endLoop()/vertex()/circle()
 * -- the "complex" drawing API (fl_vertex.cxx/fl_arc.cxx FLTK) --
 * are real too: the matrix math and path bookkeeping are pure
 * geometry (platform-independent, see the section comment above
 * pushMatrix()), and endPolygon()/endLoop() draw real
 * pixels via XFillPolygon()/XDrawLines() on Linux. This is what makes
 * fl.dial's normalDial/lineDial indicator (the knob dot / pointer line)
 * and fl.clock's hands/tick marks/round-clock face render, on top of
 * the fillDial mode the previous paragraph already covered -- see
 * `smoke-tests/dial_clock.d`: a normalDial's dot and a
 * lineDial's pointer both appear at the correct rotation for their 70%
 * value, and both a square and a round ClockOutput show three hands
 * plus 12 tick marks at the correct angles). circle() approximates
 * with a 32-sided polygon rather than FLTK's XDrawArc/XFillArc
 * shortcut, traced through the actual current transform (including
 * rotation) rather than that shortcut's axis-aligned bounding ellipse --
 * see circle()'s own doc comment. The vertex-path
 * fl_arc(double,double,double,double,double) is real too, added for
 * fl.chart's pie wedges.
 *
 * The rest of this API is real too -- see the
 * ROUND/OVAL/DIAMOND paragraph below, also covering the "rounded" family. fl_scale(double)'s uniform single-arg form; beginPoints()/
 * endPoints() and beginLine()/endLine() (the latter added
 * alongside the former as a hard dependency of endComplexPolygon()'s
 * own fallback, not originally on this item's list -- see
 * core-roadmap item 10's own note); fl_curve() (FLTK's own "incremental
 * math" forward-difference stepping, kept verbatim); and
 * beginComplexPolygon()/fl_gap()/endComplexPolygon() for
 * concave/multi-loop shapes are all real, built on the same
 * VertexKind/vertexPoints_ bookkeeping as beginPolygon()/
 * beginLoop() already used (a new VertexKind.points/line/
 * complexPolygon per new begin_*() call, since D has no shared mutable
 * `what` field the way FLTK's single driver instance does).
 * transformX()/transformY()/transformedVertex() (curve()'s
 * own hard dependencies) and loadIdentity()/loadMatrix()/
 * multMatrix()/transformDx()/transformDy() (adjacent
 * transform-stack accessors with no consumer yet, ported alongside for
 * the same "port the whole small accessor group" reasoning as other
 * small FLTK API groups elsewhere in this port) are real too.
 *
 * ARROWS: fl_draw_arrow() is real too, ported from
 * src/fl_draw_arrow.cxx -- a single triangular arrow (arrowSingle,
 * backing fl.scrollbar's end buttons and fl.counter's increment/
 * decrement buttons), a side-by-side pair (arrowDouble), or a plain
 * down arrow (arrowChoice, backing fl.choice/fl.input_choice's dropdown
 * indicator and fl.tabs's overflow indicator). Platform-
 * independent (built entirely on top of the already-real
 * fl_polygon()/fl_rectf()/fl_rect()/fl_line()), so no version(linux)
 * split is needed here, unlike most of this module.
 * FLTK branches on `Fl::is_scheme()` in two
 * places (a "chevron style" arrow variant, and a smaller/larger
 * double-arrow style for the choice arrow). The choice-arrow branch
 * (`drawArrowChoice()`'s "gtk+"/"gleam"/"plastic" cases, plus "oxy"'s
 * own dedicated `oxyArrow()`) is real and reachable via
 * `fl.core.isScheme()` -- see `drawArrow()`'s own doc
 * comment. The "chevron style" single-arrow variant stays genuinely
 * unported: unlike the choice-arrow branches, FLTK itself hardcodes
 * that one off (`gtk_chevron = false` unconditionally, reverted per
 * GitHub Issue #1117 -- dead code in real FLTK too, not something a
 * working scheme mechanism would ever reach). Not ported: the
 * debug_arrow() bounding-box visualization
 * (a compile-time-flag-gated developer aid FLTK, `#if DEBUG_ARROW`,
 * never enabled by default).
 *
 * ROUND/OVAL/DIAMOND BOXTYPES: drawBoxAt() also covers ovalBox/
 * oshadowBox/ovalFrame/oflatBox, roundUpBox/roundDownBox, and
 * diamondUpBox/diamondDownBox -- built on fl_pie()/fl_arc() (the oval family is built almost directly on them) and on
 * a 3-point fl_line()/4-point loop() (built on the already-real
 * 2-point fl_line()) for the diamond
 * family's bevel lines. See the section comment above flOvalFlatBox()
 * for the shared "Fl::box_color(c) collapses to plain fl_color(c)"
 * simplification. See `smoke-tests/round_boxtypes.d`: all 8 boxtypes render
 * distinctly -- filled/outlined/shadowed ellipses, beveled circles, and
 * beveled diamonds, not blank rectangles.
 *
 * "ROUNDED" (CSS-STYLE) BOXTYPES: roundedBox/rshadowBox/roundedFrame/
 * rflatBox are ported too,
 * via a roundedRect()/roundedRectf() primitive (a 20-point
 * lookup-table approximation of a rounded rectangle, ported from
 * Fl_Graphics_Driver::_rbox() -- see the section comment above
 * roundedRectLut for the full writeup) plus fl.core.boxBorderRadiusMax()
 * (`Fl::box_border_radius_max()`).
 *
 * GENERAL LINE STYLE: lineStyle() is real -- arbitrary dash pattern/width/cap/join,
 * used by focusRect() (see that function's own doc comment)
 * and fl.grid's drawGrid() debug-line width too.
 *
 * The 4-arg and 5-arg fl_xyline()/fl_yxline() overloads are real
 * too (added for fl.return_button's returnArrow()): pure
 * compositions of the already-real 3-arg primitives, ported from
 * Fl_Graphics_Driver::xyline()/yxline()'s own base-class bodies (which
 * are themselves just such compositions, no driver override needed --
 * same "keep the bookkeeping portable" note as the 3/4-point fl_line()
 * overloads above).
 */
module fl.draw;

import fl.image : Image;
import fl.enumerations : Color, Align, Font, Fontsize, Boxtype, ArrowType, Orientation,
    black, white, gray0, gray, dark3, light3, red, colorTable, helvetica, foregroundColor,
    symbol, screen, screenBold, zapfDingbats,
    alignClip, alignBottom, alignTop, alignLeft, alignRight, alignWrap, alignCenter,
    alignImageNextToText, alignTextOverImage, alignImageBackdrop,
    LineStyle, lineSolid, lineDash, lineDot, lineDashDot, lineDashDotDot,
    capFlat, capRound, capSquare, joinMiter, joinRound, joinBevel,
    ContrastMode, ContrastFunction, freeFont;
import fl.rect : Rect;
import fl.core;
import fl.symbols : drawSymbol;
import fl.graphics_driver : currentDriver, Point;
import std.math : sin, cos, PI, abs, sqrt;

/// Computes `int(x * currentScale())`, ported verbatim from
/// `Fl_Scalable_Graphics_Driver::floor(int x, float s)`
/// (`src/Fl_Graphics_Driver.cxx`) -- see that function's own comment for
/// why this specific `abs()`+`0.001f`-nudge formula is used rather than
/// a plain cast (accurate rounding for both positive and negative `x`).
/// The one shared rounding rule every scaled `fl.draw` primitive below
/// uses, so adjacent shapes' edges stay pixel-aligned instead of
/// drifting apart at non-integer scales.
private int scaledFloor(int x)
{
    float s = currentScale();
    if (s == 1)
        return x;
    int retval = cast(int)(abs(x) * s + 0.001f);
    return x >= 0 ? retval : -retval;
}

version (Windows)
{
    import fl.gdi_graphics_driver : GdiGraphicsDriver;
}

/// Minimal stand-in for FLTK's `fl_graphics_driver` global /
/// `Fl_Graphics_Driver::default_driver()` static -- **not** the real
/// `Fl_Graphics_Driver` port (see `fl.graphics_driver.GraphicsDriver`
/// for that, a real polymorphic base class now that `Fl_SVG_File_
/// Surface`/`Fl_PostScript_File_Device` give it real consumers -- this
/// struct predates that and deliberately stays a separate, narrower
/// thing: it exists only because a couple of samples read either the
/// module-scope `fl_graphics_driver` singleton (`test/penpal.cxx`) or
/// FLTK's static factory, `Fl_Graphics_Driver::default_driver()`
/// (`test/offscreen.cxx`), purely to call `.scale()` and detect a live
/// DPI/scale-factor change. `fl.core.screenScale(int)` is real, so
/// `scale()` here forwards to it
/// rather than returning a hardcoded `1.0` -- both call shapes see
/// the live value, same as FLTK's `Fl_Graphics_Driver::scale()` --
/// named `DisplayScaleDriver`, not `GraphicsDriver`, since that name
/// is used for the real class instead. Platform-independent:
/// `currentScale()` itself already has a
/// real cross-platform value, this stand-in never touches Xlib directly.
struct DisplayScaleDriver
{
    float scale() const { return currentScale(); }

    /// Ported from `Fl_Graphics_Driver::default_driver()`. Any instance
    /// behaves identically (this stub carries no state), so a fresh
    /// `DisplayScaleDriver.init` is as good as a real singleton
    /// reference would be.
    static DisplayScaleDriver defaultDriver() { return DisplayScaleDriver.init; }
}

DisplayScaleDriver fl_graphics_driver;

version (linux)
{
    import core.stdc.config : c_ulong;
    import fl.xlib;
    import fl.xft;

    /// Matches FLTK's `typedef Fl_Pixmap Fl_Offscreen` on X11
    /// (`FL/platform_types.H`) -- an opaque handle for
    /// `fl_create_offscreen()`/`beginOffscreen()`/etc. below.
    alias Offscreen = fl.xlib.Pixmap;

    private Display* display_;
    private GC gc_;
    private Drawable drawable_;
    private int screen_;
    private Visual* visual_;
    /// Device-pixel thickness of the *explicitly*-requested `lineStyle()`
    /// pen, when it's genuinely wide (`|width| > 1`); `0` means "no
    /// explicit wide pen active, use the default hairline." Set by
    /// `lineStyle()`, consulted by `fl_xyline()`/`fl_yxline()`'s 3-arg
    /// forms -- see those functions' own doc comments for the bug this
    /// fixes (otherwise they would assume a 1-logical-unit-thick default
    /// line regardless of any explicit width `lineStyle()` had set).
    private int explicitWideLineWidthPx_ = 0;

    /// True while the pen has a dash pattern or a round/square cap
    /// (set by `lineStyle()`). Horizontal and vertical lines then go
    /// through `XDrawLine()`, as in FLTK, instead of the filled-rectangle
    /// shortcut `fl_xyline()`/`fl_yxline()` take for plain solid lines,
    /// which can show neither dashes nor caps.
    private bool penNeedsXDrawLine_ = false;

    /// True after a `lineStyle()` call that set anything but the default
    /// hairline (a style, a width, or explicit dashes). Vertex paths
    /// then draw with the pen exactly as set, instead of widening the
    /// default hairline at whole-number scales.
    private bool penCustom_ = false;
    private Colormap colormap_;

    /**
     * Mask/shift state for packing an 8-8-8 RGB triple into a pixel
     * value matching the *active* visual's real channel layout --
     * ported from `fl_redmask`/`fl_greenmask`/`fl_bluemask`/
     * `fl_redshift`/`fl_greenshift`/`fl_blueshift`/`fl_extrashift`
     * (`Fl_Xlib_Graphics_Driver_color.cxx`, plain file-scope globals
     * there too). Populated by `figureOutVisual()` below; until that's
     * called at least once, these default to exactly the values that
     * reproduce this port's old hardcoded `(r<<16)|(g<<8)|b` formula
     * (today's real default visual on every modern X server), so
     * `fl_color()`/`fl_xpixel()` stay correct even if a caller somehow
     * draws before any window/display exists.
     */
    private ubyte visualRedMask_ = 0xFF, visualGreenMask_ = 0xFF, visualBlueMask_ = 0xFF;
    private int visualRedShift_ = 16, visualGreenShift_ = 8, visualBlueShift_ = 0, visualExtraShift_ = 0;

    /// One-time-warning latch for `figureOutVisual()`'s PseudoColor/
    /// indexed-visual fallback -- see that function's own doc comment.
    private bool warnedNonTrueColor_;

    /// The active visual's real `XPutImage()` pixel format -- queried
    /// from `XListPixmapFormats()` by `figureOutVisual()` below,
    /// consulted by `packImageBuffer()`/`putPackedImage()`
    /// so the image blit path packs pixels at the actual
    /// active depth/bits-per-pixel instead of a hardcoded 32bpp
    /// `ZPixmap`. Default `32`/`24` reproduces this port's old hardcoded
    /// behavior (today's real default visual on every modern X server).
    private int visualBitsPerPixel_ = 32;
    private int visualDepth_ = 24;

    // Xft needs its own drawing handle (XftDraw*) bound to the current
    // window, separate from the plain Xlib GC above -- recreated
    // whenever the target drawable changes. FLTK's own Xft driver
    // has a pointed comment on why this can't just be left pointing at
    // a stale window ("Xft produces errors if you destroy a window
    // whose id still exists in an XftDraw structure"), hence
    // releaseDrawable() below, called by fl.platform_x11 right before
    // XDestroyWindow().
    private XftDraw* xftDraw_;
    private Drawable xftDrawTarget_;

    /**
     * Resets every bit of display/font-connection state this module
     * tracks back to its just-loaded defaults -- for hermetic headless
     * tests only, mirroring `fl.core.resetForTest()`'s "shared static
     * state needs hermetic tests" reasoning (see CONVENTIONS.md). Nothing
     * before `fl.file_icon`'s `draw()` unittest ever issued a real X
     * call from a headless test, so this gap went unnoticed: `fl.core`'s
     * clipboard tests (`copy()`/`paste()`) call `openDisplay()` for
     * real whenever a real X server happens to be reachable (this
     * port's own dev environment), which leaves `display_`/`gc_`/the
     * font cache set for the rest of that same `dub test` process --
     * silently changing what "headless" tests elsewhere in the suite
     * actually exercise, depending on unittest execution order, unless
     * they call this first.
     */
    package(fl) void resetForTest()
    {
        display_ = null;
        gc_ = null;
        drawable_ = 0;
        screen_ = 0;
        visual_ = null;
        colormap_ = 0;
        xftDraw_ = null;
        xftDrawTarget_ = 0;
        fontCache_ = null;
        currentFontFace_ = -1;
        currentFontSize_ = 0;
        currentXftFont_ = null;
        currentFontScale_ = 1.0f;
        visualRedMask_ = visualGreenMask_ = visualBlueMask_ = 0xFF;
        visualRedShift_ = 16;
        visualGreenShift_ = 8;
        visualBlueShift_ = 0;
        visualExtraShift_ = 0;
        visualBitsPerPixel_ = 32;
        visualDepth_ = 24;
        warnedNonTrueColor_ = false;
    }

    /**
     * Internal use only; called once by fl.platform_x11 right after
     * opening the display, giving fl.draw's primitives a GC to draw
     * with (screen/visual/colormap are also needed for Xft's font
     * matching/color allocation/XftDraw creation below). Matches
     * FLTK's single GC shared by every window
     * (Fl_X11_Screen_Driver::open_display_platform(): `GC gc =
     * XCreateGC(...); Fl_Graphics_Driver::default_driver().gc(gc);`).
     */
    package(fl) void initGraphics(Display* d, GC gc, int screen, Visual* visual, Colormap colormap)
    {
        display_ = d;
        gc_ = gc;
        screen_ = screen;
        visual_ = visual;
        colormap_ = colormap;
    }

    /**
     * Derives `visualRedMask_`/etc. from the *active* visual's real
     * `red_mask`/`green_mask`/`blue_mask` -- ported verbatim from
     * `figure_out_visual()` (`Fl_Xlib_Graphics_Driver_color.cxx`): a
     * bit-scan of each mask for its lowest set bit (the shift) and run
     * length (the width), then a shared `extrashift` normalization pass
     * so a shift never needs to go negative in the final packing
     * formula. TrueColor/DirectColor only, matching this port's
     * existing "plain TrueColor visual assumed" precedent (see this
     * module's own top-of-file doc comment) -- called by
     * `fl.platform_x11.openDisplay()`/`setVisual()` once the active
     * visual (`fl_visual`) is known, passing its real
     * `redMask`/`greenMask`/`blueMask` fields (`Visual*` itself is
     * opaque in this port's bindings, see `fl.xlib.Visual`, so the
     * caller -- which holds the real `XVisualInfo` -- must extract
     * these rather than this function reading them off `visual_`
     * directly).
     *
     * Falls back to the same fixed 8-8-8 layout `visualRedMask_`/etc.
     * already default to if any
     * mask is zero -- a PseudoColor/indexed visual, out of scope here
     * (no real palette/colormap
     * support exists anywhere in this port) -- with a one-time stderr
     * warning rather than FLTK's `Fl::fatal()`. Deliberate, not a
     * gap: `fl.core.fatal()` is real, but this stays a
     * graceful, recoverable fallback on purpose -- an unsupported visual
     * degrades to a working default here, it doesn't make the library's
     * state unusable the way `fatal()`'s own contract requires.
     *
     * Also queries `XListPixmapFormats()` for `depth`'s real
     * `bits_per_pixel` (`visualBitsPerPixel_`/`visualDepth_`)
     * -- `packImageBuffer()`/
     * `putPackedImage()` below use this instead of a hardcoded 32bpp
     * `ZPixmap`. Falls back to the existing `32`/`24` default if no
     * matching format is reported (shouldn't happen against a real X
     * server, which always advertises a format for every depth any
     * visual actually uses).
     */
    package(fl) void figureOutVisual(c_ulong redMask, c_ulong greenMask, c_ulong blueMask, uint depth)
    {
        if (display_ !is null && depth != 0)
        {
            int count;
            auto formats = XListPixmapFormats(display_, &count);
            if (formats !is null)
            {
                foreach (i; 0 .. count)
                {
                    if (formats[i].depth == depth)
                    {
                        visualDepth_ = depth;
                        visualBitsPerPixel_ = formats[i].bitsPerPixel;
                        break;
                    }
                }
                XFree(formats);
            }
        }

        if (redMask == 0 || greenMask == 0 || blueMask == 0)
        {
            if (!warnedNonTrueColor_)
            {
                import std.stdio : stderr;
                stderr.writeln("fl.draw: non-TrueColor visual not supported, "
                    ~ "falling back to a plain 8-8-8 RGB layout");
                warnedNonTrueColor_ = true;
            }
            visualRedMask_ = visualGreenMask_ = visualBlueMask_ = 0xFF;
            visualRedShift_ = 16;
            visualGreenShift_ = 8;
            visualBlueShift_ = 0;
            visualExtraShift_ = 0;
            return;
        }

        static void maskShift(c_ulong mask, out int shift, out ubyte outMask)
        {
            int i = 0;
            c_ulong m = 1;
            while (m != 0 && !(mask & m)) { i++; m <<= 1; }
            int j = i;
            while (m != 0 && (mask & m)) { j++; m <<= 1; }
            shift = j - 8;
            outMask = (j - i >= 8) ? cast(ubyte) 0xFF : cast(ubyte)(0xFF - (255 >> (j - i)));
        }

        maskShift(redMask, visualRedShift_, visualRedMask_);
        maskShift(greenMask, visualGreenShift_, visualGreenMask_);
        maskShift(blueMask, visualBlueShift_, visualBlueMask_);

        int minShift = visualRedShift_;
        if (visualGreenShift_ < minShift) minShift = visualGreenShift_;
        if (visualBlueShift_ < minShift) minShift = visualBlueShift_;
        if (minShift < 0)
        {
            visualExtraShift_ = -minShift;
            visualRedShift_ -= minShift;
            visualGreenShift_ -= minShift;
            visualBlueShift_ -= minShift;
        }
        else
        {
            visualExtraShift_ = 0;
        }
    }

    unittest
    {
        // Headless (no display_ -- resetForTest()'s default): only the
        // mask/shift math is exercised, matching how a real
        // fl.platform_x11.ensureVisualFigured() call would populate
        // these from a real XVisualInfo's redMask/greenMask/blueMask.
        resetForTest();
        scope(exit) resetForTest();

        // Case 1: today's real default visual on virtually every modern
        // X server -- 24-bit color in a 32bpp ZPixmap, red in the top
        // byte. Must reproduce this port's old hardcoded
        // (r<<16)|(g<<8)|b formula exactly (regression check).
        figureOutVisual(0xFF0000, 0xFF00, 0xFF, 24);
        assert(visualRedMask_ == 0xFF && visualGreenMask_ == 0xFF && visualBlueMask_ == 0xFF);
        assert(visualRedShift_ == 16 && visualGreenShift_ == 8 && visualBlueShift_ == 0);
        assert(visualExtraShift_ == 0);
        assert(xpixel(cast(ubyte) 0x12, cast(ubyte) 0x34, cast(ubyte) 0x56)
            == ((0x12UL << 16) | (0x34UL << 8) | 0x56UL));

        // Case 2: 16-bit 5-6-5 (a common non-default depth on older/
        // embedded X servers) -- red/blue only get 5 bits, green 6.
        figureOutVisual(0xF800, 0x07E0, 0x001F, 16);
        assert(visualRedMask_ == 0xF8 && visualGreenMask_ == 0xFC && visualBlueMask_ == 0xF8);
        assert(visualRedShift_ == 11 && visualGreenShift_ == 6 && visualBlueShift_ == 0);
        assert(visualExtraShift_ == 3);

        // Case 3: 24-bit color, byte order reversed (blue in the low
        // byte, red in the middle, green at the top) -- confirms the
        // shift math isn't hardcoded to any particular channel order.
        // Every channel is a full 8 bits here, so (unlike case 2)
        // extrashift stays 0 -- that normalization only ever kicks in
        // for a channel narrower than 8 bits.
        figureOutVisual(0x00FF00, 0xFF0000, 0xFF, 24);
        assert(visualRedMask_ == 0xFF && visualGreenMask_ == 0xFF && visualBlueMask_ == 0xFF);
        assert(visualRedShift_ == 8 && visualGreenShift_ == 16 && visualBlueShift_ == 0);
        assert(visualExtraShift_ == 0);
        assert(xpixel(cast(ubyte) 0x12, cast(ubyte) 0x34, cast(ubyte) 0x56)
            == ((0x34UL << 16) | (0x12UL << 8) | 0x56UL));

        // Case 4: a PseudoColor/indexed visual (any mask zero) falls
        // back to the same fixed 8-8-8 layout, not a crash/garbage
        // shift -- see this function's own doc comment on why real
        // palette support is out of scope.
        figureOutVisual(0, 0, 0, 8);
        assert(visualRedMask_ == 0xFF && visualGreenMask_ == 0xFF && visualBlueMask_ == 0xFF);
        assert(visualRedShift_ == 16 && visualGreenShift_ == 8 && visualBlueShift_ == 0);
        assert(visualExtraShift_ == 0);
    }

    /**
     * Internal use only; called by fl.platform_x11 before invoking a
     * window's draw() cycle, so subsequent drawing calls target that
     * window. The direct (if much simplified) equivalent of FLTK's
     * Fl_Window::make_current() setting the active graphics driver's
     * current drawable before every repaint. Also (re)creates the Xft
     * drawing handle when the target actually changed -- cheap to
     * check every call, and avoids recreating it on every single
     * Expose of the same window.
     */
    package(fl) void setDrawable(Drawable d)
    {
        drawable_ = d;
        if (d != xftDrawTarget_ || xftDraw_ is null)
        {
            if (xftDraw_ !is null) XftDrawDestroy(xftDraw_);
            xftDraw_ = XftDrawCreate(display_, d, visual_, colormap_);
            xftDrawTarget_ = d;
        }
        restoreClip(); // a freshly-created xftDraw_ starts unclipped; sync it
    }

    /**
     * Internal use only; called by fl.platform_x11 right before a
     * window is destroyed. See xftDraw_'s doc comment above for why:
     * a no-op on the XftDraw half unless d is the window the cached
     * XftDraw currently targets.
     *
     * **Also clears `drawable_` when it matches `d`** (found via a
     * live `BadDrawable` crash on `XCreatePixmap()`): `drawable_` is
     * this module's own "last
     * drawn-into window" tracker, set by `setDrawable()` on every
     * repaint and read directly by `createOffscreen()` as a
     * reference drawable for a *new*, unrelated `ImageSurface`
     * (`fl.core.transientScaleDisplay()`'s own indicator popup, in
     * this case). Destroying a window must clear this: otherwise,
     * once a window is destroyed while it is still the last thing
     * painted (the common case for a short-lived popup with nothing
     * else to redraw meanwhile), `drawable_` stays a dangling XID --
     * the *next* `createOffscreen()` call anywhere would try to
     * create a Pixmap referencing an already-destroyed window and
     * fail. Resetting to `0` here reuses `createOffscreen()`'s own
     * existing "no live drawable" fallback (the root window) rather
     * than needing a new one, and matches the `gc_ !is null &&
     * drawable_ != 0` guard every direct-drawing primitive already
     * requires -- `0` is the
     * documented "nothing to draw into" sentinel throughout this
     * module.
     */
    package(fl) void releaseDrawable(Drawable d)
    {
        if (xftDraw_ !is null && d == xftDrawTarget_)
        {
            XftDrawDestroy(xftDraw_);
            xftDraw_ = null;
            xftDrawTarget_ = 0;
        }
        if (drawable_ == d)
            drawable_ = 0;
    }

    /**
     * Creates an off-screen `Pixmap` sized `(w, h)` at the current
     * screen's default depth -- the buffer `fl.platform_x11.flushDamage()`
     * draws a `DoubleWindow` into before blitting it onto the real
     * window (real double-buffering, `CONVENTIONS.md`/`PORTING.md`'s
     * `fl.double_window` row). `referenceDrawable` is only used to tell
     * `XCreatePixmap()` which screen to create it on (any drawable on
     * that screen works, per the Xlib manual) -- the caller passes the
     * window's own xid, since that's guaranteed to already exist and be
     * on the right screen. Returns `0` (matching every other "no
     * display"/degenerate-size guard in this module) if there's no live
     * display or `w`/`h` isn't positive.
     */
    package(fl) fl.xlib.Pixmap createOffscreenBuffer(Drawable referenceDrawable, int w, int h)
    {
        if (display_ is null || w <= 0 || h <= 0) return 0;
        return XCreatePixmap(display_, referenceDrawable, cast(uint) w, cast(uint) h,
            cast(uint) XDefaultDepth(display_, screen_));
    }

    /// Frees a buffer created by createOffscreenBuffer(). A no-op for
    /// `0`, matching every other uncache()-style function in this port.
    package(fl) void freeOffscreenBuffer(fl.xlib.Pixmap p)
    {
        if (p == 0) return;
        XFreePixmap(display_, p);
    }

    /**
     * Copies `(w, h)` from off-screen buffer `src` at `(srcX, srcY)`
     * onto the *current* drawable (see `setDrawable()`) at
     * `(destX, destY)` -- the blit half of real double-buffering, via a
     * plain `XCopyArea()` on this module's own shared GC (same
     * technique `fl_scroll()` already uses for its same-drawable
     * scroll-blit, just cross-drawable here). Ported from the
     * `XCopyArea()` call at the end of FLTK's
     * `Fl_X11_Window_Driver::flush_double()` -- the driver-agnostic core
     * of that function (the surrounding `#if FLTK_USE_CAIRO` blocks
     * there are Cairo-specific bookkeeping this port's concrete,
     * non-Cairo `fl.draw` has no equivalent of, and doesn't need: the
     * off-screen-buffer-then-blit *algorithm* itself never depended on
     * which graphics driver is doing the actual drawing).
     */
    package(fl) void copyOffscreen(fl.xlib.Pixmap src, int srcX, int srcY, int w, int h, int destX, int destY)
    {
        if (gc_ is null || w <= 0 || h <= 0) return;
        // Dest only, not src -- src addresses the offscreen buffer's own
        // coordinate space, unaffected by the current drawable's
        // translate offset. Matches FLTK's own equivalent call
        // exactly: `XCopyArea(..., (x+offset_x_)*scale(), (y+offset_y_)*
        // scale())` (`Fl_Xlib_Graphics_Driver.cxx`).
        XCopyArea(display_, src, drawable_, gc_, srcX, srcY, cast(uint) w, cast(uint) h,
            destX + offsetX_, destY + offsetY_);
    }

    /**
     * Copies `(w, h)` directly from one pixmap to another (or to any
     * other drawable) at `(srcX, srcY)` -> `(destX, destY)`, with both
     * ends named explicitly -- unlike `copyOffscreen()` above (which
     * always targets the *current* drawable), this doesn't touch or
     * depend on `drawable_` at all. Needed by `fl.image_surface.
     * ImageSurface.mask()`, whose own doc comment (matching FLTK's
     * `Fl_Image_Surface::mask()`) requires the surface NOT be current
     * when called, so `copyOffscreen()`'s "current drawable" assumption
     * doesn't apply. Ported from the direct `XCopyArea(fl_display,
     * offscreen, shape_data_->background, (GC)driver()->gc(), ...)`
     * call in `Fl_Xlib_Image_Surface_Driver::mask()` (`src/drivers/
     * Xlib/Fl_Xlib_Image_Surface_Driver.cxx`), including its preceding
     * `driver()->restore_clip()` call (re-syncs the shared GC's clip
     * state to this module's own tracked clip stack, in case it was
     * left stale by unrelated prior drawing).
     */
    package(fl) void copyPixmapToPixmap(fl.xlib.Pixmap src, fl.xlib.Pixmap dst,
        int srcX, int srcY, int w, int h, int destX, int destY)
    {
        if (gc_ is null || w <= 0 || h <= 0) return;
        restoreClip();
        XCopyArea(display_, src, dst, gc_, srcX, srcY, cast(uint) w, cast(uint) h, destX, destY);
    }

    /// Stack of drawables saved across nested beginOffscreen()/
    /// fl_end_offscreen() pairs -- FLTK's Fl_Surface_Device::
    /// push_current()/pop_current() is a real stack too (any surface
    /// can itself draw into another offscreen mid-frame).
    private Drawable[] offscreenStack_;

    /// Ported from `fl_create_offscreen(int, int)` (`FL/fl_draw.H`) --
    /// FLTK's own current implementation is layered on top of
    /// `Fl_Image_Surface` (a small buffer registry mapping each
    /// `Fl_Offscreen` handle back to its owning surface object). This
    /// goes straight to the lower-level primitive `Fl_Image_Surface`
    /// itself reaches for on X11 (`XCreatePixmap()`, wrapped as
    /// `createOffscreenBuffer()` and also used by `fl.double_window`'s
    /// buffering), a smaller implementation of the same public
    /// contract. `Offscreen` is a
    /// plain `alias` for `fl.xlib.Pixmap` (matching FLTK's own
    /// `typedef Fl_Pixmap Fl_Offscreen` on X11), so `0`/`Offscreen.init`
    /// still means "no buffer" the same way callers already expect.
    Offscreen createOffscreen(int w, int h)
    {
        if (display_ is null) return 0;
        Drawable reference = drawable_ != 0 ? drawable_ : XRootWindow(display_, screen_);
        return createOffscreenBuffer(reference, w, h);
    }

    /// Ported from `fl_delete_offscreen(Fl_Offscreen)`.
    void deleteOffscreen(Offscreen ctx)
    {
        freeOffscreenBuffer(ctx);
    }

    /// Ported from `fl_begin_offscreen(Fl_Offscreen)`: redirects
    /// subsequent drawing calls to `ctx` until the matching
    /// `endOffscreen()`, saving whatever drawable was active so it
    /// can be restored (nestable, matching FLTK's own
    /// push_current()/pop_current() stack).
    void beginOffscreen(Offscreen ctx)
    {
        offscreenStack_ ~= drawable_;
        setDrawable(ctx);
    }

    /// Ported from `fl_end_offscreen()`.
    void endOffscreen()
    {
        if (offscreenStack_.length == 0) return;
        Drawable prev = offscreenStack_[$ - 1];
        offscreenStack_.length -= 1;
        setDrawable(prev);
    }

    /// Ported from `fl_copy_offscreen(int, int, int, int, Fl_Offscreen,
    /// int, int)`: thin reordering wrapper over `copyOffscreen()`
    /// (`destX, destY, w, h, src, srcX, srcY` here vs. that function's
    /// `src, srcX, srcY, w, h, destX, destY` -- matching FLTK's own
    /// public parameter order, which puts the destination first).
    void copyOffscreen(int x, int y, int w, int h, Offscreen pixmap, int srcx, int srcy)
    {
        copyOffscreen(pixmap, srcx, srcy, w, h, x, y);
    }

    /// Ported from `fl_rescale_offscreen(Fl_Offscreen&)`: still a no-op
    /// here -- it exists in FLTK to resize a buffer in place when the
    /// screen's scale factor changes. `fl.core.screenScale(int)` is real,
    /// but this module's own offscreen-buffer helpers don't consult it,
    /// so there is nothing for this function to do yet.
    void rescaleOffscreen(ref Offscreen ctx) { }

    /// Applies the current top-of-clip-stack rectangle (if any) to
    /// both the plain Xlib GC and the Xft drawing handle -- two
    /// separate clip states in Xlib/Xft's own APIs (XftDraw manages
    /// its own GC internally, not gc_), so both need setting on every
    /// pushClip()/popClip(). Called by those, and by setDrawable()
    /// (a freshly-created xftDraw_ starts unclipped and needs syncing
    /// to match whatever clip is already active mid-draw-cycle).
    ///
    /// Adds the current `offsetX_`/`offsetY_` (see that field's own doc
    /// comment) to the rectangle actually handed to the GC/XftDraw --
    /// `clipStack_` itself stores rectangles in the same *pre-offset*
    /// logical space every drawing call's own (x,y) arguments are given
    /// in (a caller clipping to a widget's own local bounds passes the
    /// same coordinates it would pass to `fl_rectf()`), so the offset
    /// has to be injected here, at the one point the clip actually
    /// becomes real device coordinates -- otherwise clip and drawing
    /// would silently end up in two different coordinate spaces whenever
    /// a translate is active. Ported from FLTK's own equivalent
    /// split: `Fl_Xlib_Graphics_Driver::push_clip()` never touches
    /// `offset_x_`/`offset_y_` either, only `restore_clip()`'s call to
    /// `scale_clip()` does, right before `XSetRegion()`.
    ///
    /// Also scales via `scaledFloor()`, applied *after* the offset --
    /// matching `Fl_Xlib_Graphics_
    /// Driver::scale_clip()`'s own `floor(r->rects[i].x1 + offset_x_,
    /// f)` order (offset first, then scale) and its own edge-alignment
    /// formula (`w = floor(x2+offset_x_, f) - x`, same
    /// `scaledFloor(x2)-scaledFloor(x)` shape `fl_rectf()` already
    /// uses) -- without this, drawing (already scaled) and clipping
    /// (left at the old FLTK-unit rectangle) would silently disagree
    /// the moment `currentScale() != 1`, clipping away part of any
    /// scaled-up content. At `currentScale() == 1` this is exactly the
    /// pre-scaling behavior.
    private void restoreClip()
    {
        if (gc_ is null) return;
        auto c = currentClip();
        if (!c.active)
        {
            XSetClipMask(display_, gc_, 0); // None: no clipping
            if (xftDraw_ !is null) XftDrawSetClip(xftDraw_, null); // None: no clipping
        }
        else
        {
            int sx = scaledFloor(c.x + offsetX_);
            int sy = scaledFloor(c.y + offsetY_);
            int sw = scaledFloor(c.x + (c.w > 0 ? c.w : 0) + offsetX_) - sx;
            int sh = scaledFloor(c.y + (c.h > 0 ? c.h : 0) + offsetY_) - sy;
            XRectangle r;
            r.x = cast(short) sx;
            r.y = cast(short) sy;
            r.width = cast(ushort)(sw > 0 ? sw : 0);
            r.height = cast(ushort)(sh > 0 ? sh : 0);
            XSetClipRectangles(display_, gc_, 0, 0, &r, 1, clipRectanglesUnsorted);
            if (xftDraw_ !is null) XftDrawSetClipRectangles(xftDraw_, 0, 0, &r, 1);
        }
    }
}
else
{
    private void restoreClip() {}

    /// No display/font-connection state to reset on this platform yet
    /// (see the `version (linux)` `resetForTest()` above for what this
    /// mirrors) -- kept as a real, callable no-op rather than omitted so
    /// unittests that import it selectively (`import fl.draw :
    /// resetForTest;`, e.g. `fl.multi_label`'s) compile on every platform.
    package(fl) void resetForTest() {}
}

/**
 * Windows offscreen-surface support -- ported from `fl_create_offscreen()`/
 * `fl_begin_offscreen()`/`fl_end_offscreen()`/`fl_delete_offscreen()`/
 * `fl_copy_offscreen()`/`fl_rescale_offscreen()` (`FL/fl_draw.H`) via the
 * real WinAPI bodies in `src/drivers/GDI/Fl_GDI_Image_Surface_Driver.cxx`
 * + `Fl_GDI_Graphics_Driver_color.cxx`'s `fl_makeDC()` (both
 * in FLTK's source), read before writing any of this rather than
 * guessed: FLTK's own current implementation layers these on top of
 * `Fl_Image_Surface` (a small buffer-registry class, see
 * `fl.image_surface`'s own doc comment for why this port's Linux side
 * skips that layer too), but the actual GDI mechanics underneath are
 * simple enough to port directly at this level, matching the Linux
 * `version (linux)` block above's own "smaller implementation of the
 * same public contract" precedent.
 *
 * **`Offscreen` is a plain `alias` for `HBITMAP`**, matching FLTK's
 * own `typedef HBITMAP Fl_Offscreen` on WinAPI (`FL/platform_types.H`) --
 * a bare GDI bitmap object, no device context permanently attached to it
 * (unlike this port's own per-window `privateDcCache_` in
 * `fl.gl_window_driver`, a different, GL-specific caching decision --
 * see that module's own doc comment). Every function below that needs to
 * actually draw into or read from one creates a *temporary* compatible
 * DC around it via `makeDcFor()` and destroys that DC (not the bitmap)
 * when done, exactly matching FLTK's own `fl_makeDC()`/`DeleteDC()`
 * pairing at each of `set_current()`/`end_current()`/`copy_offscreen()`'s
 * own call sites -- the bitmap itself is the only thing that persists
 * across a `beginOffscreen()`/`endOffscreen()` cycle, holding the actual
 * pixel data.
 */
version (Windows)
{
    import core.sys.windows.windows;
    import fl.gdi_graphics_driver : GdiGraphicsDriver;

    alias Offscreen = HBITMAP;

    /// Ported from `fl_makeDC(HBITMAP)` (`Fl_GDI_Graphics_Driver_color.cxx`):
    /// a fresh DC compatible with the screen, with `bitmap` selected into
    /// it -- the caller owns the returned DC and must `DeleteDC()` it
    /// (never the bitmap) once done. `SetTextAlign`/`SetBkMode` match
    /// FLTK's own "calling GetDC seems to always reset these" fixup
    /// (`Fl_win32.cxx`'s `fl_GetDC()`), applied here too since text can be
    /// drawn into an offscreen surface the same as any on-screen one.
    private HDC makeDcFor(HBITMAP bitmap)
    {
        HDC dc = CreateCompatibleDC(null);
        SetTextAlign(dc, TA_BASELINE | TA_LEFT);
        SetBkMode(dc, TRANSPARENT);
        SelectObject(dc, bitmap);
        return dc;
    }

    /// Ported from `Fl_GDI_Image_Surface_Driver`'s constructor: prefers
    /// the currently-active `GdiGraphicsDriver`'s own DC as the
    /// `CreateCompatibleBitmap()` reference (matching FLTK's `gc ?
    /// gc : fl_GetDC(0)`), falling back to the real desktop screen DC
    /// when no window has painted yet (e.g. called before any window's
    /// first `show()`, same as the Linux `createOffscreen()` above
    /// falling back to the root window).
    ///
    /// Uses the real `GetDC(null)` (released
    /// via `ReleaseDC()`, not `DeleteDC()` -- a `GetDC()`-obtained DC is
    /// owned by the desktop, not by this call) as the fallback reference, not
    /// `CreateCompatibleDC(null)`: `fl_GetDC()` calls the real Win32
    /// `GetDC()`, retrieving a DC for an actual device (the screen, when
    /// passed a null/desktop window), which correctly reports the
    /// screen's real color depth, whereas `CreateCompatibleDC(null)`
    /// creates a brand-new *memory* DC -- and by a well-known,
    /// documented GDI quirk, every freshly-created memory DC starts out
    /// with a default **1x1 monochrome** bitmap selected into it,
    /// regardless of the "compatible with" device's own real depth.
    /// `CreateCompatibleBitmap(screenDc, w, h)` would then create a bitmap
    /// "compatible with" *that default monochrome bitmap*, not the
    /// screen -- so every `ImageSurface` built before any window ever
    /// painted would get a 1-bit
    /// black-or-white offscreen buffer instead of a real color one,
    /// silently corrupting every subsequent GDI(+) draw call into it.
    /// This matches FLTK's own `fl_GetDC(0)` exactly.
    Offscreen createOffscreen(int w, int h)
    {
        if (w <= 0 || h <= 0) return null;
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        HDC reference = (driver !is null && driver.hdc() !is null) ? driver.hdc() : null;
        if (reference !is null) return CreateCompatibleBitmap(reference, w, h);
        HDC screenDc = GetDC(null);
        auto bmp = CreateCompatibleBitmap(screenDc, w, h);
        ReleaseDC(null, screenDc);
        return bmp;
    }

    /// Ported from `fl_delete_offscreen(Fl_Offscreen)` (`~Fl_GDI_Image_
    /// Surface_Driver()`'s `DeleteObject((HBITMAP)offscreen)` half).
    void deleteOffscreen(Offscreen ctx)
    {
        if (ctx !is null) DeleteObject(ctx);
    }

    /// One saved "what to restore drawing to afterward" entry per nested
    /// `beginOffscreen()`/`endOffscreen()` pair -- `savedHdc` is the DC
    /// `GdiGraphicsDriver` was targeting before this call (restored by
    /// `endOffscreen()`), `ownDc` is the temporary DC `makeDcFor()`
    /// created for `ctx` itself (destroyed by `endOffscreen()`). Matches
    /// the Linux `offscreenStack_` above's own role exactly, just saving
    /// an `HDC` pair instead of a `Drawable`.
    private struct OffscreenFrame { HDC savedHdc; HDC ownDc; }
    private OffscreenFrame[] offscreenStack_;

    /// Ported from `fl_begin_offscreen(Fl_Offscreen)` /
    /// `Fl_GDI_Image_Surface_Driver::set_current()`: redirects
    /// `GdiGraphicsDriver`'s own DC to a fresh `makeDcFor(ctx)` until the
    /// matching `endOffscreen()`, saving whatever DC was active so it can
    /// be restored (nestable, matching FLTK's own `SaveDC()`-based
    /// nesting and this port's identical Linux-side stack).
    void beginOffscreen(Offscreen ctx)
    {
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        if (driver is null || ctx is null) return;
        offscreenStack_ ~= OffscreenFrame(driver.hdc(), makeDcFor(ctx));
        driver.setHdc(offscreenStack_[$ - 1].ownDc);
    }

    /// Ported from `fl_end_offscreen()` / `Fl_GDI_Image_Surface_Driver::
    /// end_current()`.
    void endOffscreen()
    {
        if (offscreenStack_.length == 0) return;
        auto frame = offscreenStack_[$ - 1];
        offscreenStack_.length -= 1;
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        if (driver !is null) driver.setHdc(frame.savedHdc);
        DeleteDC(frame.ownDc);
    }

    /// Ported from `Fl_GDI_Graphics_Driver::copy_offscreen()`: blits
    /// `(w, h)` from offscreen bitmap `src` at `(srcX, srcY)` onto the
    /// *currently active* DC (whatever `GdiGraphicsDriver` is targeting)
    /// at `(destX, destY)` -- a temporary `makeDcFor(src)` stands in for
    /// FLTK's own `CreateCompatibleDC()`+`SelectObject()` pair around
    /// the `BitBlt()` call, destroyed immediately after, matching
    /// FLTK's own `SaveDC()`/`RestoreDC()`/`DeleteDC()` sequence
    /// (that save/restore pair itself isn't needed here -- this port's
    /// `dc` is freshly created for this call alone, never reused
    /// afterward, unlike FLTK's occasional DC-caching call sites).
    void copyOffscreen(Offscreen src, int srcX, int srcY, int w, int h, int destX, int destY)
    {
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        if (driver is null || driver.hdc() is null || w <= 0 || h <= 0) return;
        HDC srcDc = makeDcFor(src);
        BitBlt(driver.hdc(), destX, destY, w, h, srcDc, srcX, srcY, SRCCOPY);
        DeleteDC(srcDc);
    }

    /// Ported from `fl_copy_offscreen(int, int, int, int, Fl_Offscreen,
    /// int, int)`: same reordering-wrapper role as the Linux overload
    /// above.
    void copyOffscreen(int x, int y, int w, int h, Offscreen pixmap, int srcx, int srcy)
    {
        copyOffscreen(pixmap, srcx, srcy, w, h, x, y);
    }

    /// Ported from `fl_rescale_offscreen(Fl_Offscreen&)` -- still a
    /// no-op here, same reasoning as the Linux overload above (nothing
    /// in this port's image/offscreen-buffer handling consults the
    /// scale factor yet).
    void rescaleOffscreen(ref Offscreen ctx) { }
}

// ---------------------------------------------------------------------
// Clipping (the clip-stack half of Fl_Graphics_Driver/
// Fl_Xlib_Graphics_Driver -- src/Fl_Graphics_Driver.cxx +
// src/drivers/Xlib/Fl_Xlib_Graphics_Driver_rect.cxx)
// ---------------------------------------------------------------------
//
// Real (and platform-independent -- see below) now. FLTK's clip
// stack holds a real X11 `Region` per level (`Fl_Region`, opaque,
// built via XCreateRegion()/XUnionRectWithRegion()/XIntersectRegion()),
// which supports arbitrary non-rectangular shapes in general. This
// port never needs that generality: every push_clip() call FLTK
// ever makes is a single axis-aligned rectangle, and the intersection
// of two axis-aligned rectangles is always another axis-aligned
// rectangle -- so a plain rectangle stack (ClipEntry[]) is exactly as
// capable for every case this port exercises, with no XRegion API
// needed at all. The bookkeeping (pushClip()/popClip()/notClipped()/
// clipBox()) is pure arithmetic, so it's real on every platform, not
// just Linux; only restoreClip() -- applying the current clip to the
// GC/XftDraw -- is Xlib-specific and lives in the version(linux) block
// below.
//
// FLTK's 16-bit X-coordinate-space pre-clamping (`clip_rect()`) matters
// not just for a *window's own* size, but for
// arbitrary drawing coordinates a caller can still pass (a widget
// scrolled to a large virtual offset, a degenerate/huge computed
// rectangle, etc.), which is exactly the case FLTK's own comment on
// `clip_rect()` describes guarding against. `clipRectToCoordSpace()`
// below (a direct, pure-arithmetic port of `Fl_Xlib_Graphics_Driver::
// clip_rect(int&,int&,int&,int&)`, headless-testable since it's just
// integer math), wired into `fl_rectf()` only -- matching FLTK's own
// real asymmetry exactly: `Fl_Xlib_Graphics_Driver::rectf_unscaled()`
// (the filled-rect path `fl_rectf()` reaches) calls `clip_rect()`
// itself, but `rect_unscaled()` (the unfilled-border path `fl_rect()`
// reaches) never does -- FLTK simply doesn't guard that one, so
// this port doesn't either. The Color-taking convenience overload
// delegates to `fl_rectf()`, so `fl_rectf(...,c)` is covered too. Not
// wired into every other primitive FLTK also gates on it elsewhere
// (arcs, polygons, the Xft text-position guards) -- those stay
// unclamped, same as before; this closes the specific, named "16-bit
// X-coordinate pre-clamping" gap for the one primitive FLTK itself
// actually guards, not a full port of every call site FLTK happens
// to use it at.

/// The 16-bit signed range X11's wire protocol packs coordinates into
/// (`INT16`) -- matching FLTK's own `clip_max_ = 32760` (`2**15 - 8`,
/// `Fl_Xlib_Graphics_Driver.cxx`) and `clip_min() { return -clip_max_; }`
/// (`Fl_Xlib_Graphics_Driver.H`) exactly, a small safety margin under
/// the hard `+/-32768` protocol limit.
private enum int xCoordClipMax = 32760;

/// Ported from `Fl_Xlib_Graphics_Driver::clip_rect(int&, int&, int&,
/// int&)` (`src/drivers/Xlib/Fl_Xlib_Graphics_Driver_rect.cxx`) --
/// see its own doc comment there for the full reasoning (reproduced
/// here since this is this port's only copy of it): returns `true`
/// (leaving `x`/`y`/`w`/`h` untouched) if the rectangle is degenerate
/// (`w<=0`/`h<=0`) or entirely outside the valid 16-bit coordinate
/// range -- callers should draw nothing in that case. Otherwise clamps
/// `x`/`y`/`w`/`h` to fit within the valid range (shrinking only, never
/// growing) and returns `false` -- X itself still clips the result to
/// the actual clip region/window bounds, exactly as FLTK's own doc
/// comment notes ("X can handle it and clip unneeded pixels"); this
/// only prevents the *coordinate values themselves* from overflowing
/// the protocol's 16-bit fields.
package(fl) bool clipRectToCoordSpace(ref int x, ref int y, ref int w, ref int h)
{
    enum int cmin = -xCoordClipMax;
    enum int cmax = xCoordClipMax;

    if (w <= 0 || h <= 0) return true;
    if (x + w < cmin || y + h < cmin) return true;
    if (x > cmax || y > cmax) return true;

    if (x < cmin) { w -= (cmin - x); x = cmin; }
    if (y < cmin) { h -= (cmin - y); y = cmin; }
    if (x + w > cmax) w = cmax - x;
    if (y + h > cmax) h = cmax - y;
    return false;
}

unittest
{
    // Fully outside (case (b)/(c) in FLTK's own doc comment):
    // untouched, returns true.
    int x = -100000, y = 0, w = 10, h = 10;
    assert(clipRectToCoordSpace(x, y, w, h) == true);
    assert(x == -100000 && w == 10); // untouched

    x = 100000; y = 0; w = 10; h = 10;
    assert(clipRectToCoordSpace(x, y, w, h) == true);

    // Degenerate: zero/negative area.
    x = 0; y = 0; w = 0; h = 10;
    assert(clipRectToCoordSpace(x, y, w, h) == true);

    // Straddling the boundary: clamped, not rejected, and the clamped
    // rectangle's right edge lands exactly at cmax.
    x = xCoordClipMax - 5; y = 0; w = 1000; h = 10;
    assert(clipRectToCoordSpace(x, y, w, h) == false);
    assert(x == xCoordClipMax - 5);
    assert(x + w == xCoordClipMax);

    // Fully inside: no change at all.
    x = 10; y = 20; w = 30; h = 40;
    assert(clipRectToCoordSpace(x, y, w, h) == false);
    assert(x == 10 && y == 20 && w == 30 && h == 40);
}

/// One level of the clip stack. `active = false` means "no clipping in
/// effect at this level" (distinct from an empty/zero-area clip, which
/// is `active = true` with w = h = 0 -- FLTK's "make empty clip
/// region" case for a degenerate pushClip()).
private struct ClipEntry
{
    bool active;
    int x, y, w, h;

    /// Whether `pushClip()` told `fl.graphics_driver.currentDriver`
    /// about this entry when it was pushed -- `pushNoClip()`
    /// leaves this `false` even while a driver is active (see that
    /// function's own doc comment on why it has no driver hook), so
    /// `popClip()` must track this per-entry rather than just checking
    /// `currentDriver !is null` again at pop time: that alone can't
    /// tell a `pushClip()`-pushed entry (which *did* notify the driver)
    /// from a `pushNoClip()`-pushed one (which didn't), and
    /// calling the driver's `popClip()` for an entry it was never told
    /// about would desync its own nesting bookkeeping (e.g.
    /// `SvgGraphicsDriver`'s open `<g clip-path="...">` count).
    bool driverNotified;
}
private ClipEntry[] clipStack_;

private ClipEntry currentClip()
{
    return clipStack_.length ? clipStack_[$ - 1] : ClipEntry(false);
}

/**
 * The current cumulative coordinate offset every native drawing
 * primitive adds to the raw device coordinates it actually hands to
 * Xlib -- ported from `Fl_Xlib_Graphics_Driver::offset_x_`/`offset_y_`
 * (`Fl_Xlib_Graphics_Driver.H`/`.cxx`), plain reversible-offset state
 * there too. Zero by default, so every existing on-screen window draw
 * call (which never pushes a translate) is a complete no-op through
 * this mechanism -- only `fl.widget_surface.WidgetSurface.translate()`/
 * `untranslate()` (via `CopySurface`/`ImageSurface`, both of which draw
 * into an offscreen Pixmap through this exact native path) ever changes
 * these. See `pushTranslate()`/
 * `popTranslate()` below for the reversible push/pop pair, and this
 * module's own "Clipping" section for why the clip-rectangle stack
 * above needs no separate offset field of its own -- `restoreClip()`
 * adds this same offset at the one point a clip actually gets applied
 * to the GC, matching FLTK's own `scale_clip()`-in-`restore_clip()`
 * split exactly (see that function's doc comment).
 */
private int offsetX_, offsetY_;

/// Fixed-size save stack for `pushTranslate()`/`popTranslate()` --
/// FLTK caps this at `FL_XLIB_GRAPHICS_TRANSLATION_STACK_SIZE`
/// with an overflow warning (`Fl::warning()`, not ported); this port
/// uses a plain growable `int[]` pair instead, matching this module's
/// usual "GC makes manual capacity management unnecessary" precedent
/// (see `CONVENTIONS.md`) rather than replicating the fixed-array-plus-
/// overflow-check design.
private int[] translateStackX_, translateStackY_;

/// Adds (dx, dy) to the current coordinate offset (`offsetX_`/
/// `offsetY_`), saving the previous value for the matching
/// `popTranslate()` -- ported from `Fl_Xlib_Graphics_Driver::
/// translate_all(int, int)`. Reversible and nestable, same as
/// `pushClip()`/`popClip()`. Re-applies whatever clip is currently on
/// the clip stack (`restoreClip()`) so an already-active clip doesn't
/// keep reflecting the *old* offset until some unrelated later
/// `pushClip()`/`popClip()` happens to refresh it -- FLTK's own
/// `translate_all()` doesn't do this (it relies on every real call site
/// pairing a translate with a fresh `push_clip()` right after, which
/// happens to hold for its only real caller too, `Fl_Widget_Surface::
/// draw()`), but doing it unconditionally here is strictly more robust
/// at effectively no cost (translate is never on a hot path -- only
/// `CopySurface`/`ImageSurface` ever call it) and removes a latent
/// footgun for any future caller that doesn't happen to follow that
/// same pattern.
package(fl) void pushTranslate(int dx, int dy)
{
    translateStackX_ ~= offsetX_;
    translateStackY_ ~= offsetY_;
    offsetX_ += dx;
    offsetY_ += dy;
    restoreClip();
}

/// Undoes the most recent `pushTranslate()` -- ported from
/// `Fl_Xlib_Graphics_Driver::untranslate_all()`. A no-op (matching
/// `popClip()`'s own underflow guard) if the stack is already empty.
/// Re-applies the current clip afterward, same reasoning as
/// `pushTranslate()`'s own doc comment.
package(fl) void popTranslate()
{
    if (translateStackX_.length == 0) return;
    offsetX_ = translateStackX_[$ - 1];
    offsetY_ = translateStackY_[$ - 1];
    translateStackX_ = translateStackX_[0 .. $ - 1];
    translateStackY_ = translateStackY_[0 .. $ - 1];
    restoreClip();
}

unittest
{
    // Pure bookkeeping -- no display needed. Reset first/after in case
    // an earlier test left the stack non-empty (same "shared static
    // state needs hermetic tests" reasoning as clipStack_'s own tests).
    offsetX_ = offsetY_ = 0;
    translateStackX_ = [];
    translateStackY_ = [];
    scope(exit)
    {
        offsetX_ = offsetY_ = 0;
        translateStackX_ = [];
        translateStackY_ = [];
    }

    assert(offsetX_ == 0 && offsetY_ == 0);
    pushTranslate(10, 20);
    assert(offsetX_ == 10 && offsetY_ == 20);
    pushTranslate(5, -3); // nested -- cumulative, not absolute
    assert(offsetX_ == 15 && offsetY_ == 17);
    popTranslate();
    assert(offsetX_ == 10 && offsetY_ == 20); // restored to the pre-nested value
    popTranslate();
    assert(offsetX_ == 0 && offsetY_ == 0);
    popTranslate(); // underflow -- a no-op, matching popClip()'s own guard
    assert(offsetX_ == 0 && offsetY_ == 0);
}

/// Intersects (x,y,w,h) with other (if other is active); returns an
/// active-but-empty (w=h=0) result when they don't overlap at all.
private ClipEntry intersectClip(int x, int y, int w, int h, ClipEntry other)
{
    if (!other.active) return ClipEntry(true, x, y, w, h);
    int x1 = x > other.x ? x : other.x;
    int y1 = y > other.y ? y : other.y;
    int x2 = (x + w < other.x + other.w) ? x + w : other.x + other.w;
    int y2 = (y + h < other.y + other.h) ? y + h : other.y + other.h;
    int nw = x2 - x1;
    int nh = y2 - y1;
    return ClipEntry(true, x1, y1, nw > 0 ? nw : 0, nh > 0 ? nh : 0);
}

/// Pushes a new clip rectangle, intersected with whatever clip (if
/// any) is already in effect -- ported from Fl_Graphics_Driver::
/// push_clip(). A degenerate (w<=0 or h<=0) rect pushes an empty clip
/// (nothing at all is visible until the matching popClip()), matching
/// FLTK exactly. This bookkeeping runs unconditionally regardless
/// of `fl.graphics_driver.currentDriver` (unlike this module's other
/// dispatched leaves, there's no "either/or" here -- see that field's
/// own doc comment); when a driver *is* active, it's also notified of
/// the final intersected rectangle via `currentDriver.pushClip()`.
void pushClip(int x, int y, int w, int h)
{
    ClipEntry newClip = (w <= 0 || h <= 0)
        ? ClipEntry(true, x, y, 0, 0)
        : intersectClip(x, y, w, h, currentClip());
    if (currentDriver !is null)
    {
        newClip.driverNotified = true;
        currentDriver.pushClip(newClip.x, newClip.y, newClip.w, newClip.h);
    }
    clipStack_ ~= newClip;
    restoreClip();
}

/// Pushes an unbounded ("no clipping in effect") entry onto the clip
/// stack, regardless of what clip (if any) was already active --
/// ported from `Fl_Graphics_Driver::push_no_clip()`. Popped the same
/// way as `pushClip()`, via `popClip()`. **Deliberately doesn't notify
/// `fl.graphics_driver.currentDriver`** (see `fl.graphics_driver.
/// GraphicsDriver.popClip()`'s own doc comment for the real FLTK
/// SVG behavior this skips, and why) -- `popClip()` knows not to call
/// the driver back for an entry pushed this way.
void pushNoClip()
{
    clipStack_ ~= ClipEntry(false);
    restoreClip();
}

/// Pops the most recent pushClip(), restoring whatever clip (if any)
/// was in effect before it. A no-op (with no warning -- Fl::warning()
/// itself isn't ported) if the stack is already empty, matching
/// FLTK's underflow guard minus the warning message. Notifies
/// `fl.graphics_driver.currentDriver.popClip()` iff the entry being
/// popped was itself pushed with a driver notification (see
/// `ClipEntry.driverNotified`'s own doc comment for why that can't
/// just be "is a driver currently active").
void popClip()
{
    if (clipStack_.length)
    {
        auto popped = clipStack_[$ - 1];
        clipStack_ = clipStack_[0 .. $ - 1];
        if (popped.driverNotified && currentDriver !is null) currentDriver.popClip();
    }
    restoreClip();
}

/// Discards every level of the clip stack unconditionally, regardless
/// of any `pushClip()`/`pushNoClip()` left un-popped -- ported from the
/// *effect* of `fl_clip_region(0)`, which `Fl_WinAPI_Printer_Driver::
/// begin_page()` calls at the start of every printed page. FLTK's
/// own clip stack (`Fl_Graphics_Driver::rstack`) is a member of each
/// `Fl_Graphics_Driver` instance, so a fresh per-job driver already
/// starts with an empty stack and that call is close to a no-op there;
/// `clipStack_` above is a single module-level stack shared by every
/// surface/driver instead (see this module's own "Real clipping" note),
/// so without an explicit reset here, a fresh print/export driver's
/// very first `pushClip()` would intersect against whatever rectangle
/// the *last* on-screen draw happened to leave on top of the stack,
/// silently cropping the whole page down to an unrelated small area.
/// Does not need to touch `currentDriver`'s own native clip state: the
/// one real caller (`fl.printer_win32.Printer.beginPage()`) always runs
/// against a brand-new HDC/`GraphicsDriver` pair that starts unclipped
/// on its own, so clearing the logical stack here is both necessary and
/// sufficient.
package(fl) void resetClipStack()
{
    clipStack_ = [];
}

/**
 * Reports whether any part of (x,y,w,h) could be visible under the
 * current clip -- true if there's no active clip, or if (x,y,w,h)
 * overlaps it at all (even partially); false only if they're
 * completely disjoint. Ported from Fl_Xlib_Graphics_Driver::
 * not_clipped() (the `XRectInRegion() != RectangleOut` case,
 * specialized to a single rectangle instead of a general region).
 */
bool notClipped(int x, int y, int w, int h)
{
    auto c = currentClip();
    if (!c.active) return true;
    // An empty clip (w<=0 or h<=0, e.g. from a degenerate pushClip())
    // has no area to overlap -- the general overlap test below assumes
    // both rectangles are non-empty, and gives a wrong answer at this
    // boundary (a half-open interval of width 0 isn't "approached
    // from the left", it's simply empty) if that guard is skipped.
    if (c.w <= 0 || c.h <= 0) return false;
    return x + w > c.x && y + h > c.y && x < c.x + c.w && y < c.y + c.h;
}

/// The color set by the most recent fl_color(Color) call (FLTK's
/// `Fl_Graphics_Driver::color_`, `FL_BLACK` at startup). Tracked here
/// rather than in the version(linux) block since the getter and the
/// save/restore idiom it exists for (`auto old = fl_color(); ...;
/// fl_color(old);`, used throughout FLTK's example/test programs)
/// don't depend on having a real driver underneath.
private Color currentColor_ = black;

/**
 * Decodes c into its RGB components. Every Color in this port is
 * either a "free" (packed-RGB) color -- any value with a nonzero bit
 * above the low byte, matching FLTK's `if (i & 0xffffff00)` check
 * (`Fl::get_color()`/`Fl_Xlib_Graphics_Driver::color()`) -- or an
 * index into the system color table (fl.enumerations.colorTable),
 * which already packs its entries in the same `0xRRGGBB00` layout, so
 * both cases decode identically once picked apart. Shared by every
 * place in this module that needs raw RGB from a Color: fl_color()'s
 * Xlib pixel, xftColorFor()'s Xft color, the color-math functions
 * below (colorAverage()/inactive()/contrast()), and (public,
 * matching FLTK's own `Fl::get_color()` being a real public API,
 * not draw-specific) fl.image's RGBImage.colorAverage()/desaturate().
 */
void colorToRgb8(Color c, out ubyte r, out ubyte g, out ubyte b)
{
    // fl.core.colorTableEntry() reads the *mutable* color table
    // (fl.core.setColor()/Fl::set_color()'s backing store) rather than
    // the immutable default palette directly, so a setColor()/
    // background()/foreground() call is reflected here immediately --
    // see that function's own doc comment.
    uint rgb = (c & 0xFFFFFF00) ? c : fl.core.colorTableEntry(c);
    r = cast(ubyte)(rgb >> 24);
    g = cast(ubyte)(rgb >> 16);
    b = cast(ubyte)(rgb >> 8);
}

/// Packs r, g, b into a "free" (packed-RGB) Color -- ported from the
/// inline `rgbColor(uchar,uchar,uchar)` in Enumerations.H (kept
/// here rather than fl.enumerations for the same import-cycle reason
/// darker()/lighter() are: it's a direct building block of
/// colorAverage() below, which needs to live in fl.draw). Special-
/// cased so pure black stays representable as the compact `black`
/// index rather than becoming a big packed value that happens to
/// decode to black too, matching FLTK exactly.
Color rgbColor(ubyte r, ubyte g, ubyte b)
{
    if (r == 0 && g == 0 && b == 0) return black;
    return (cast(Color) r << 24) | (cast(Color) g << 16) | (cast(Color) b << 8);
}

/**
 * Sets the color used by subsequent drawing calls. Dispatches to
 * `fl.graphics_driver.currentDriver` first when one is active (see that
 * module's own doc comment for the null-means-native dispatch model);
 * otherwise real on Linux: decodes c (see colorToRgb8()) and sets it as
 * the shared GC's foreground pixel, packed for the *active* visual's
 * real channel layout via `visualRedMask_`/etc. (see `figureOutVisual()`
 * -- for today's real default 24-bit TrueColor visual this produces the
 * exact same pixel value this port's old hardcoded `(r<<16)|(g<<8)|b`
 * formula did).
 */
void fl_color(Color c)
{
    currentColor_ = c;
    if (currentDriver !is null)
    {
        currentDriver.color(c);
        return;
    }
    version (linux)
    {
        ubyte r, g, b;
        colorToRgb8(c, r, g, b);
        c_ulong pixel = xpixel(r, g, b);
        if (gc_ !is null) XSetForeground(display_, gc_, pixel);
    }
}

version (linux)
{
    /**
     * The X pixel value packing r/g/b for the *active* visual's real
     * channel layout -- ported from `fl_xpixel(uchar,uchar,uchar)`'s
     * TrueColor branch (`Fl_Xlib_Graphics_Driver_color.cxx`):
     * `(((r&mask)<<shift) + ...) >> extrashift` using the mask/shift
     * state `figureOutVisual()` derived from `fl_visual`'s real
     * `red_mask`/`green_mask`/`blue_mask`. Shared by `fl_color(Color)`
     * above and `fl_xpixel(Color)` below.
     */
    c_ulong xpixel(ubyte r, ubyte g, ubyte b)
    {
        c_ulong v = (cast(c_ulong)(r & visualRedMask_) << visualRedShift_)
            + (cast(c_ulong)(g & visualGreenMask_) << visualGreenShift_)
            + (cast(c_ulong)(b & visualBlueMask_) << visualBlueShift_);
        return v >> visualExtraShift_;
    }

    /**
     * The X pixel value `fl_color(c)` would set as the GC foreground --
     * ported from `fl_xpixel(Fl_Color)` (`Fl_Xlib_Graphics_Driver_
     * color.cxx`). Same TrueColor-only simplification as `fl_color()`
     * itself: uses the active visual's real mask/shift layout (see
     * `figureOutVisual()`), not a hardcoded 8-8-8 formula, but still no
     * PseudoColor/indexed-colormap support (see that function's own
     * fallback). Used by `source/test/image.d`/`tiled_image.d`'s
     * `-v <visid>` diagnostic path ("make sure black is allocated in
     * overlay visuals") -- a colormap-era concern this port's
     * always-TrueColor drawing has no real equivalent for, so this is
     * honest-but-narrow: it returns the same value fl_color() would
     * use, it just doesn't allocate anything.
     */
    c_ulong xpixel(Color c)
    {
        ubyte r, g, b;
        colorToRgb8(c, r, g, b);
        return xpixel(r, g, b);
    }
}

/// Returns the last color set via fl_color(Color) -- real on every
/// platform, since it only reads currentColor_ rather than querying a
/// driver.
Color fl_color()
{
    return currentColor_;
}

// ---------------------------------------------------------------------
// Ellipse/pie/circle drawing (fl_draw.cxx's integer arc family +
// Fl_Xlib_Graphics_Driver_arci.cxx)
// ---------------------------------------------------------------------
//
// Real on Linux now (XDrawArc/XFillArc). FLTK reaches these through
// a scale-transform wrapper (Fl_Scalable_Graphics_Driver::arc()/pie(),
// which adjusts x/y/w/h for the current display scale factor before
// calling arc_unscaled()/pie_unscaled()) that this port doesn't need
// (no scaling support exists, see fl.draw's other "assumes scale=1"
// simplifications) -- at scale=1 that wrapper's arithmetic reduces
// exactly to a direct XDrawArc/XFillArc call with (w-1,h-1) as the
// bounding box (matching XDrawRectangle's own "size is an offset to
// the far corner" convention, same as fl_rect()), so that's what's
// implemented directly here rather than replicating the wrapper's
// scale-derived math (which would produce the same w-1/h-1 result at
// scale=1 anyway, just through a lot more indirection). Angles are in
// degrees, counterclockwise from 3 o'clock, matching X11's own
// convention exactly (FLTK's doc comment says the same thing) --
// so no conversion beyond the degrees-to-64ths-of-a-degree scaling
// XDrawArc/XFillArc want.

/// Draws the outline of an elliptical arc inscribed in (x,y,w,h), from
/// angle a1 to a2. Dispatches to `fl.graphics_driver.currentDriver`
/// first when one is active; otherwise real on Linux (XDrawArc), scaled
/// the same `scaledFloor(x+w)-scaledFloor(x)-s`/half-line-width-inset
/// way `fl_rect()` is -- FLTK's real
/// `Fl_Scalable_Graphics_Driver::arc(int,...)` additionally factors in
/// the active line width (`line_width_`), which this port's arc/pie
/// functions don't track at all (no consumer needs it);
/// skipped here as a documented simplification, same class as
/// `fl_rect()`'s own. At `currentScale() == 1` this reduces exactly to
/// the pre-scaling `w-1`/`h-1` formula.
void fl_arc(int x, int y, int w, int h, double a1, double a2)
{
    if (currentDriver !is null)
    {
        currentDriver.arc(x, y, w, h, a1, a2);
        return;
    }
    version (linux)
    {
        if (gc_ is null || drawable_ == 0 || w <= 0 || h <= 0) return;
        int s = cast(int) currentScale();
        int d = s / 2;
        int sx = scaledFloor(x) + d, sy = scaledFloor(y) + d;
        int sw = scaledFloor(x + w) - scaledFloor(x) - s;
        int sh = scaledFloor(y + h) - scaledFloor(y) - s;
        if (sw <= 0 || sh <= 0) return;
        XDrawArc(display_, drawable_, gc_, sx + offsetX_, sy + offsetY_, cast(uint) sw, cast(uint) sh,
            cast(int)(a1 * 64), cast(int)((a2 - a1) * 64));
    }
}

/// Draws a filled pie slice/ellipse inscribed in (x,y,w,h), from angle
/// a1 to a2. Dispatches to `fl.graphics_driver.currentDriver` first
/// when one is active; otherwise real on Linux -- an outline (XDrawArc)
/// plus the fill (XFillArc), matching FLTK's own pie_unscaled(),
/// which draws both so the slice's edge looks the same as a plain
/// fl_arc(). Scaled via the same `scaledFloor(x+w)-scaledFloor(x)-1`
/// edge-alignment fl_rect()'s formula reduces to at `currentScale() ==
/// 1` (derived from FLTK's real scaled `pie(int,...)` +
/// `pie_unscaled()` pair, which nets out to exactly this once their
/// `scale()>=3`-only `extra` fringe adjustment is skipped -- a
/// documented simplification, same class as `fl_arc()`'s own).
void fl_pie(int x, int y, int w, int h, double a1, double a2)
{
    if (currentDriver !is null)
    {
        currentDriver.pie(x, y, w, h, a1, a2);
        return;
    }
    version (linux)
    {
        if (gc_ is null || drawable_ == 0 || w <= 0 || h <= 0) return;
        int sx = scaledFloor(x), sy = scaledFloor(y);
        int sw = scaledFloor(x + w) - sx - 1;
        int sh = scaledFloor(y + h) - sy - 1;
        if (sw <= 0 || sh <= 0) return;
        int a1i = cast(int)(a1 * 64);
        int a2i = cast(int)((a2 - a1) * 64);
        XDrawArc(display_, drawable_, gc_, sx + offsetX_, sy + offsetY_, cast(uint) sw, cast(uint) sh, a1i, a2i);
        XFillArc(display_, drawable_, gc_, sx + offsetX_, sy + offsetY_, cast(uint) sw, cast(uint) sh, a1i, a2i);
    }
}

/**
 * Draws a filled circle bounded by (x,y,d,d) in color c. Same as
 * `fl_pie(x,y,d,d,0,360)` except at small diameters (<= 6px), where
 * XDrawArc/XFillArc render poorly on many systems (FLTK's own
 * rationale) -- approximated there with 1-3 filled rectangles instead,
 * ported from `Fl_Scalable_Graphics_Driver::draw_circle()`'s `switch
 * (scaled_d)` table. `scaled_d` (`currentScale() > 1.0 ? cast(int)(d *
 * currentScale()) : d`) only
 * decides *which strategy* renders best at the final on-screen size --
 * the `fl_rectf()`/`fl_pie()` calls below still pass plain FLTK-unit
 * `x`/`y`/`d` unchanged, exactly like FLTK's own `rectf(x0,y0,...)`/
 * `pie(x0,y0,...)` calls (its own *scaled* virtual methods, not
 * `_unscaled`), since those two primitives already scale internally
 * now. fl_color() is preserved across the call, matching FLTK.
 */
void drawCircle(int x, int y, int d, Color c)
{
    Color old = fl_color();
    fl_color(c);
    float s = currentScale();
    int scaledD = (s > 1.0f) ? cast(int)(d * s) : d;
    switch (scaledD)
    {
    case 6:
        fl_rectf(x + 2, y, d - 4, d);
        fl_rectf(x + 1, y + 1, d - 2, d - 2);
        fl_rectf(x, y + 2, d, d - 4);
        break;
    case 3: .. case 5:
        fl_rectf(x + 1, y, d - 2, d);
        fl_rectf(x, y + 1, d, d - 2);
        break;
    case 1: .. case 2:
        fl_rectf(x, y, d, d);
        break;
    default:
        fl_pie(x, y, d, d, 0.0, 360.0);
        break;
    }
    fl_color(old);
}

// ---------------------------------------------------------------------
// "Complex" scalable drawing: transform stack + vertex path
// (fl_vertex.cxx/fl_arc.cxx FLTK) -- added for fl.dial's/
// fl.clock's draw(), the first widgets in this port needing the
// rotate/scale-then-trace-a-shape drawing style rather than plain
// axis-aligned boxes/lines. Real: the matrix math and path
// bookkeeping are pure geometry (platform-independent, ported straight
// from Fl_Graphics_Driver::mult_matrix()/rotate()/vertex()), and the
// actual pixels come from XDrawLines()/XFillPolygon() on Linux (a no-op
// stub pair elsewhere, same as every other Xlib-backed primitive in
// this module). FLTK's fl_scale(double) (uniform single-arg),
// beginPoints()/endPoints()/beginLine()/endLine(),
// curve(), and the beginComplexPolygon()/fl_gap()/
// endComplexPolygon() flavor for concave/multi-loop shapes are all
// real too (see the module
// header comment's own writeup; drawCheck() still draws its concave
// hexagon directly via XFillPolygon() rather than through this API, see
// that function's own comment, since it never needs rotation/scaling).
// The vertex-path fl_arc(double,double,double,double,double) is real
// too, added for fl.chart's pie-wedge drawing (see that function's own
// doc comment).
// ---------------------------------------------------------------------

private struct Matrix
{
    double a = 1, b = 0, c = 0, d = 1, x = 0, y = 0;
}

private Matrix currentMatrix_ = Matrix.init;
private Matrix[] matrixStack_;

private void matrixConcat(double a, double b, double c, double d, double x, double y)
{
    Matrix o;
    o.a = a * currentMatrix_.a + b * currentMatrix_.c;
    o.b = a * currentMatrix_.b + b * currentMatrix_.d;
    o.c = c * currentMatrix_.a + d * currentMatrix_.c;
    o.d = c * currentMatrix_.b + d * currentMatrix_.d;
    o.x = x * currentMatrix_.a + y * currentMatrix_.c + currentMatrix_.x;
    o.y = x * currentMatrix_.b + y * currentMatrix_.d + currentMatrix_.y;
    currentMatrix_ = o;
}

/// Pushes a copy of the current transform matrix, so a later
/// fl_pop_matrix() can restore it. Ported from
/// Fl_Graphics_Driver::push_matrix(); FLTK errors on overflow of its
/// fixed 32-deep array -- this port's stack is a plain dynamic array, so
/// there's nothing to overflow.
void pushMatrix()
{
    matrixStack_ ~= currentMatrix_;
}

/// Pops the transform matrix stack, restoring the previous transform.
/// Ported from Fl_Graphics_Driver::pop_matrix(); a pop with nothing
/// pushed is a no-op here rather than FLTK's Fl::error() (that
/// reporting mechanism isn't ported -- every caller in this port
/// balances its push/pop pairs anyway, same as FLTK's).
void popMatrix()
{
    if (matrixStack_.length == 0) return;
    currentMatrix_ = matrixStack_[$ - 1];
    matrixStack_ = matrixStack_[0 .. $ - 1];
}

/// Sets the transform matrix to identity, discarding any accumulated
/// translate/scale/rotate (but not the push/pop stack itself). Ported
/// from Fl_Graphics_Driver::load_identity() (`m = m0`) -- Matrix.init is
/// this port's equivalent of FLTK's fixed identity constant `m0`.
void loadIdentity()
{
    currentMatrix_ = Matrix.init;
}

/// Sets the transform matrix directly (replacing it, not concatenating
/// -- unlike multMatrix()/fl_translate()/fl_scale()/fl_rotate()).
/// Ported from Fl_Graphics_Driver::load_matrix().
void loadMatrix(double a, double b, double c, double d, double x, double y)
{
    currentMatrix_ = Matrix(a, b, c, d, x, y);
}

/// Concatenates an arbitrary transform onto the current one: `X' = aX +
/// cY + x`, `Y' = bX + dY + y`. Ported from Fl_Graphics_Driver::
/// mult_matrix() -- the general form fl_translate()/fl_scale()/
/// fl_rotate() are each a special case of (this port's private
/// matrixConcat() already implements the shared math; this is just the
/// public entry point FLTK also exposes directly).
void multMatrix(double a, double b, double c, double d, double x, double y)
{
    matrixConcat(a, b, c, d, x, y);
}

/// Concatenates a translation by (x, y) onto the current transform.
/// Ported from Fl_Graphics_Driver::translate().
void fl_translate(double x, double y)
{
    matrixConcat(1, 0, 0, 1, x, y);
}

/// Concatenates a scale by (x, y) onto the current transform. Ported
/// from fl_draw.H's 2-arg fl_scale(double,double) inline.
void fl_scale(double x, double y)
{
    matrixConcat(x, 0, 0, y, 0, 0);
}

/// Concatenates a uniform scale by f (both axes) onto the current
/// transform. Ported from fl_draw.H's 1-arg fl_scale(double) inline --
/// `fl_scale(x, x)`.
void fl_scale(double f)
{
    fl_scale(f, f);
}

/// Concatenates a rotation by d degrees (counterclockwise) onto the
/// current transform. Ported from Fl_Graphics_Driver::rotate(),
/// including its exact-angle special cases for 0/90/180/270 (avoids
/// sin()/cos() floating-point noise at exactly the angles fl.dial's
/// tick marks and fl.clock's hands hit every frame).
void fl_rotate(double d)
{
    if (d == 0) return;
    double s, c;
    if (d == 90) { s = 1; c = 0; }
    else if (d == 180) { s = 0; c = -1; }
    else if (d == 270 || d == -90) { s = -1; c = 0; }
    else { s = sin(d * PI / 180); c = cos(d * PI / 180); }
    matrixConcat(c, -s, s, c, 0, 0);
}

/// What kind of path vertex() is currently accumulating, set by
/// beginPolygon()/beginLoop()/beginPoints()/beginLine()/
/// beginComplexPolygon() and consumed by the matching fl_end_*().
/// `none` between paths (or if a path is ended without ever being begun,
/// in which case fl_vertex()/fl_end_*() are no-ops -- matches FLTK's
/// own `n` staying 0).
private enum VertexKind { none, loop, polygon, points, line, complexPolygon }
private VertexKind vertexKind_ = VertexKind.none;

/// Index into vertexPoints_ where the current sub-loop of a
/// fl_begin_complex_polygon() path started -- FLTK's `gap_`, reset
/// by beginComplexPolygon() and advanced by fl_gap().
private size_t gapIndex_;

/// Point count of each sub-loop `fl_gap()` has closed so far -- FLTK's
/// `counts[]`/`numcount` (`Fl_GDI_Graphics_Driver::gap()`), passed to
/// `GraphicsDriver.endComplexPolygonParts()`.
private int[] gapCounts_;

/// A short-int point in the accumulating vertex path. Deliberately not
/// fl.xlib's XPoint -- the path buffer itself is pure, platform-
/// independent bookkeeping (same design as the ClipEntry[] clip stack
/// above), only converted to a real XPoint[] at the point of the actual
/// Xlib call inside the version(linux) endPolygon()/endLoop()
/// bodies below.
private struct VPoint { short x, y; }
private VPoint[] vertexPoints_;

/// Appends (x, y) to vertexPoints_, multiplied by `currentScale()`
/// first then truncated to short,
/// matching FLTK's `Fl_Scalable_Graphics_Driver::transformed_
/// vertex()`/`::vertex()`, both of which multiply by `scale()` right
/// before calling the plain-cast `transformed_vertex0()` this port's
/// `appendVertexPoint()` corresponds to -- this is the single
/// choke-point every vertex-path entry (`vertex()`, `transformedVertex()`,
/// `circle()`, `curve()`) funnels through, so scaling it here covers
/// the whole family at once. Deduplicates a point equal to the
/// immediately preceding one (FLTK's own rationale: a matrix that
/// squashes two logical vertices onto the same device pixel shouldn't
/// produce a degenerate zero-length segment) -- comparing the already-
/// scaled values, matching FLTK's own post-scale dedup (its
/// dedup check in `transformed_vertex0()` runs on the same `x,y` its
/// caller already multiplied by `scale()`).
///
/// Skips the `screenScale()` multiply for a driver that declares
/// `wantsUnscaledVertices()` -- without this, at
/// scale > 1, a GL pane would draw its shapes
/// both larger and shifted further right than the native pane's,
/// badly enough to run off the window. See that method's own doc
/// comment on `fl.graphics_driver.GraphicsDriver` for the full
/// reasoning (a real split in FLTK's own class hierarchy: GL/
/// PostScript/SVG output all want raw, unscaled coordinates, while
/// this port's native Xlib path and the Windows GDI/GDI+ drivers all
/// want them pre-scaled to device pixels). Deliberately *not* keyed
/// on plain `currentDriver !is null` -- unlike Linux, where a null
/// `currentDriver` means "native Xlib," Windows' `currentDriver` is
/// *always* a real `GdiGraphicsDriver`/`GdiPlusGraphicsDriver` (see
/// `fl.platform_win32.ensureGraphicsDriver()`), which still wants
/// scaling; checking the driver's own declared preference instead
/// keeps both platforms' native on-screen path correct.
private void appendVertexPoint(double xf, double yf)
{
    float s = (currentDriver !is null && currentDriver.wantsUnscaledVertices())
        ? 1.0f : currentScale();
    appendVertexPointScaled(cast(short)(xf * s), cast(short)(yf * s));
}

/// Appends an already-device-pixel-scaled point directly, with no
/// further scaling -- the dedup-and-append half `appendVertexPoint()`
/// above shares, matching FLTK's own split between `vertex()`
/// (matrix-transform + multiply by `scale()`, then call
/// `transformed_vertex0()`) and `transformed_vertex0()` itself (store
/// only, no scaling of its own -- matching `Fl_Xlib_
/// Graphics_Driver::gap()`, `src/drivers/Xlib/Fl_Xlib_Graphics_Driver_
/// vertex.cxx`, which calls `transformed_vertex0(short_point[gap_].x,
/// short_point[gap_].y)` directly, bypassing `vertex()`'s own scaling
/// step entirely since that point is already scaled). `fl_gap()` needs
/// exactly this: it re-appends a sub-loop's own *closing* point, which
/// it already has as an already-scaled `VPoint` pulled straight out of
/// `vertexPoints_` -- passing that back through the scaling
/// `appendVertexPoint(double,double)` above would scale it a *second* time
/// (at any scale other than 1.0, a wildly-misplaced point, once for the
/// sketch's own explicit `fl_gap()` call and again for
/// `endComplexPolygon()`'s own internal one).
private void appendVertexPointScaled(short x, short y)
{
    if (vertexPoints_.length == 0
        || x != vertexPoints_[$ - 1].x || y != vertexPoints_[$ - 1].y)
        vertexPoints_ ~= VPoint(x, y);
}

/// Starts a closed, filled path (vertices added via vertex(), ended
/// by fl_end_polygon()). Ported from Fl_Graphics_Driver::begin_polygon().
void beginPolygon()
{
    vertexKind_ = VertexKind.polygon;
    vertexPoints_.length = 0;
}

/// Starts a closed, unfilled path (vertices added via vertex(), ended
/// by fl_end_loop()). Ported from Fl_Graphics_Driver::begin_loop().
void beginLoop()
{
    vertexKind_ = VertexKind.loop;
    vertexPoints_.length = 0;
}

/// Starts an unconnected list of points (vertices added via vertex(),
/// ended by fl_end_points()). Ported from Fl_Graphics_Driver::
/// begin_points() (src/fl_vertex.cxx).
void beginPoints()
{
    vertexKind_ = VertexKind.points;
    vertexPoints_.length = 0;
}

/// Starts an open polyline (vertices added via vertex(), ended by
/// fl_end_line()). Ported from Fl_Graphics_Driver::begin_line()
/// (src/fl_vertex.cxx).
void beginLine()
{
    vertexKind_ = VertexKind.line;
    vertexPoints_.length = 0;
}

/// Starts a filled path that may be concave, have holes, or consist of
/// several disconnected loops (vertices added via vertex(), loops
/// separated by fl_gap(), ended by endComplexPolygon()). Ported
/// from Fl_Graphics_Driver::begin_complex_polygon() (`begin_polygon();
/// gap_ = 0;` -- reusing VertexKind.complexPolygon rather than
/// VertexKind.polygon so endComplexPolygon() can tell which
/// end-drawing rule applies, since D has no shared mutable `what` field
/// FLTK's single driver instance uses to remember which begin_*()
/// started the current path).
void beginComplexPolygon()
{
    vertexKind_ = VertexKind.complexPolygon;
    vertexPoints_.length = 0;
    gapIndex_ = 0;
    gapCounts_.length = 0;
}

/// Separates loops of a fl_begin_complex_polygon() path -- ported from
/// Fl_Xlib_Graphics_Driver::gap() (src/drivers/Xlib/
/// Fl_Xlib_Graphics_Driver_vertex.cxx): drops trailing points equal to
/// the current sub-loop's own start point, then either re-appends that
/// start point to close the sub-loop and advances gapIndex_ to begin
/// the next one (if at least 3 points remain), or discards the
/// degenerate sub-loop entirely by truncating back to gapIndex_.
/// Harmless to call before the first vertex, after the last, or
/// several times in a row, matching FLTK's own documented contract.
///
/// Guarded on `vertexKind_ == complexPolygon`, unlike FLTK's own
/// gap() (which has no such guard) -- a deliberate, safety-only
/// deviation: gapIndex_ is reset only by beginComplexPolygon(), so
/// it can be left stale and nonzero by a previous path if fl_gap() is
/// ever called outside a begin/end bracket (e.g. after some other
/// beginPolygon()/beginLoop() call reused vertexPoints_); an
/// unguarded discard branch (`vertexPoints_.length = gapIndex_;`) would
/// then *grow* the array with zero-filled points rather than truncate
/// it. endComplexPolygon() below still calls this *before*
/// resetting vertexKind_ to none, so the guard doesn't interfere with
/// its own use of this function.
void fl_gap()
{
    if (vertexKind_ != VertexKind.complexPolygon) return;

    while (vertexPoints_.length > gapIndex_ + 2
        && vertexPoints_[$ - 1] == vertexPoints_[gapIndex_])
        vertexPoints_.length = vertexPoints_.length - 1;

    if (vertexPoints_.length > gapIndex_ + 2)
    {
        auto p = vertexPoints_[gapIndex_];
        appendVertexPointScaled(p.x, p.y); // p is already scaled -- see that function's own doc comment
        gapCounts_ ~= cast(int)(vertexPoints_.length - gapIndex_);
        gapIndex_ = vertexPoints_.length;
    }
    else
    {
        vertexPoints_.length = gapIndex_;
    }
}

/// Adds (x, y), transformed by the current matrix, as the next point in
/// the path started by fl_begin_polygon()/fl_begin_loop(). Ported from
/// Fl_Graphics_Driver::vertex(): `x*m.a + y*m.c + m.x, x*m.b + y*m.d +
/// m.y` is exactly matrixConcat()'s translation-column formula applied to
/// the point (x, y).
void vertex(double x, double y)
{
    if (vertexKind_ == VertexKind.none) return;
    appendVertexPoint(
        x * currentMatrix_.a + y * currentMatrix_.c + currentMatrix_.x,
        x * currentMatrix_.b + y * currentMatrix_.d + currentMatrix_.y);
}

/// Transforms (x, y) through the current matrix, x-component only.
/// Ported from Fl_Graphics_Driver::transform_x() (fl_transform_x() in
/// fl_draw.H) -- pure geometry, no display needed.
double transformX(double x, double y)
{
    return x * currentMatrix_.a + y * currentMatrix_.c + currentMatrix_.x;
}

/// ditto, y-component. Ported from Fl_Graphics_Driver::transform_y().
double transformY(double x, double y)
{
    return x * currentMatrix_.b + y * currentMatrix_.d + currentMatrix_.y;
}

/// Transforms a distance (x, y) through the current matrix's rotation/
/// scale only (translation dropped) -- x-component. Ported from
/// Fl_Graphics_Driver::transform_dx(). No consumer in this port yet
/// (added alongside transformX()/transformY() for the same
/// "port the whole small accessor group, not just the one call site
/// needs" reasoning as loadIdentity()/loadMatrix()/
/// multMatrix() below).
double transformDx(double x, double y)
{
    return x * currentMatrix_.a + y * currentMatrix_.c;
}

/// ditto, y-component. Ported from Fl_Graphics_Driver::transform_dy().
double transformDy(double x, double y)
{
    return x * currentMatrix_.b + y * currentMatrix_.d;
}

/// Adds (xf, yf) -- already in transformed (device) coordinates, unlike
/// fl_vertex() -- as the next point in the current path. Ported from
/// Fl_Graphics_Driver::transformed_vertex(); the direct building block
/// curve() below needs (its own forward-difference stepping works
/// entirely in already-transformed space, see that function's own doc
/// comment) and the "rounded" boxtype family's corner-arc points use
/// too (bypassing fl_vertex() deliberately, matching FLTK's own
/// `_rbox()` calling `transformed_vertex()` rather than `vertex()` --
/// see roundedRect()'s own doc comment).
void transformedVertex(double xf, double yf)
{
    if (vertexKind_ == VertexKind.none) return;
    appendVertexPoint(xf, yf);
}

/// Adds a circle of radius r centered at (x, y) to the current path.
/// Ported from Fl_Scalable_Graphics_Driver::circle() collapsed to this
/// port's fixed scale of 1: transforms the center through the current
/// matrix, derives the transformed x/y radii from the matrix's column
/// magnitudes (so a preceding fl_scale()/fl_rotate() -- exactly how
/// fl.dial/fl.clock use it -- produces an ellipse of the right size),
/// then approximates with a 32-gon rather than FLTK's XDrawArc/
/// XFillArc "ellipse_unscaled()" shortcut: that shortcut only exists to
/// special-case circles drawn outside a begin/end pair with no rotation
/// in effect (fl.dial's fillDial mode already gets a real XDrawArc/
/// XFillArc via fl_pie()/fl_arc() directly, see that module), and would
/// draw the *unrotated* bounding ellipse instead of tracing an actual
/// path through the current (possibly rotated) transform, which is
/// exactly what beginPolygon()/beginLoop() need here.
void circle(double x, double y, double r)
{
    if (vertexKind_ == VertexKind.none) return;

    double rx = r * (currentMatrix_.c != 0
        ? sqrt(currentMatrix_.a * currentMatrix_.a + currentMatrix_.c * currentMatrix_.c)
        : (currentMatrix_.a < 0 ? -currentMatrix_.a : currentMatrix_.a));
    double ry = r * (currentMatrix_.b != 0
        ? sqrt(currentMatrix_.b * currentMatrix_.b + currentMatrix_.d * currentMatrix_.d)
        : (currentMatrix_.d < 0 ? -currentMatrix_.d : currentMatrix_.d));
    double cx = x * currentMatrix_.a + y * currentMatrix_.c + currentMatrix_.x;
    double cy = x * currentMatrix_.b + y * currentMatrix_.d + currentMatrix_.y;
    enum segments = 32;
    for (int i = 0; i <= segments; i++)
    {
        double t = 2 * PI * i / segments;
        appendVertexPoint(cx + rx * cos(t), cy + ry * sin(t));
    }
}

/// Adds a partial arc (from start to end, in degrees, counterclockwise
/// from 3 o'clock -- same convention as the int-based fl_arc()/
/// fl_pie() overloads above) to the current path, without beginning or
/// ending it itself -- meant to be called inside a
/// beginPolygon()/beginLoop() block, added for
/// fl.chart's pie/special-pie wedges (draw_piechart(), which brackets
/// each call with an explicit vertex(cx, cy) to complete the wedge
/// shape, exactly like FLTK). Ported from
/// Fl_Graphics_Driver::arc(double,double,double,double,double)
/// (src/fl_arc.cxx), but stepped in a fixed number of segments (scaled
/// to the arc's angular span) rather than FLTK's adaptive
/// chord-length-epsilon algorithm -- same simplification, same
/// rationale as circle() just above (this port doesn't need
/// adaptive resolution at the sizes it's actually drawn at). Unlike
/// circle(), this computes each point in local (untransformed)
/// space and calls vertex() to apply the current matrix -- exactly
/// what FLTK's own fl_arc.cxx does (`fl_vertex(x+X, y+Y)` inside
/// its stepping loop) and, unlike circle()'s manual
/// radius-from-column-magnitude shortcut, handles a skewed transform
/// correctly too (though nothing in this port produces a skew yet).
void fl_arc(double x, double y, double r, double start, double end)
{
    double span = end - start;
    int segments = cast(int)(32 * (span < 0 ? -span : span) / 360.0 + 0.5);
    if (segments < 1) segments = 1;

    for (int i = 0; i <= segments; i++)
    {
        double deg = start + span * i / segments;
        double t = deg * PI / 180.0;
        vertex(x + r * cos(t), y - r * sin(t));
    }
}

unittest
{
    // fl_arc(): pure vertex-path bookkeeping, no display needed. A
    // quarter arc from 0 to 90 degrees (counterclockwise from 3
    // o'clock, matching the int-based fl_arc()/fl_pie() overloads'
    // convention) starts at (r, 0) and ends at (0, -r) -- screen Y
    // decreases as the angle increases, since screen Y grows downward.
    beginLoop();
    fl_arc(0, 0, 10, 0, 90);
    assert(vertexPoints_.length >= 2);
    assert(vertexPoints_[0] == VPoint(10, 0));
    assert(vertexPoints_[$ - 1] == VPoint(0, -10));
    endLoop(); // safe no-op without a live X display (gc_ is null)
}

/**
 * Adds a cubic Bezier curve from (X0,Y0) to (X3,Y3) (control points
 * X1,Y1/X2,Y2) to the current path, without beginning or ending it --
 * meant to be called inside a beginPolygon()/beginLoop()/
 * fl_begin_line()/fl_begin_points() block. Ported from src/fl_curve.cxx's
 * Fl_Graphics_Driver::curve(): pre-transforms all 4 control points via
 * transformX()/transformY() up front, then does all further
 * stepping arithmetic and appends (transformedVertex(), not
 * vertex()) directly in that already-transformed space -- FLTK's
 * own "incremental math" forward-difference algorithm (its own doc
 * comment doubts it's optimal and invites a better one; kept verbatim
 * rather than substituting a different curve-flattening approach, same
 * faithful-unless-reasoned-otherwise default this whole port follows),
 * clamping the adaptive segment count to [9, 100].
 */
void curve(double X0, double Y0, double X1, double Y1, double X2, double Y2, double X3, double Y3)
{
    double x = transformX(X0, Y0);
    double y = transformY(X0, Y0);

    transformedVertex(x, y);

    double x1 = transformX(X1, Y1);
    double y1 = transformY(X1, Y1);
    double x2 = transformX(X2, Y2);
    double y2 = transformY(X2, Y2);
    double x3 = transformX(X3, Y3);
    double y3 = transformY(X3, Y3);

    double a = abs((x - x2) * (y3 - y1) - (y - y2) * (x3 - x1));
    double b = abs((x - x3) * (y2 - y1) - (y - y3) * (x2 - x1));
    if (b > a) a = b;

    int nSeg = cast(int)(sqrt(a) / 4);
    if (nSeg > 1)
    {
        if (nSeg > 100) nSeg = 100; // make huge curves not hang forever
        if (nSeg < 9) nSeg = 9; // make tiny curves look bearable

        double e = 1.0 / nSeg;

        double xa = x3 - 3 * x2 + 3 * x1 - x;
        double xb = 3 * (x2 - 2 * x1 + x);
        double xc = 3 * (x1 - x);
        double dx1 = ((xa * e + xb) * e + xc) * e;
        double dx3 = 6 * xa * e * e * e;
        double dx2 = dx3 + 2 * xb * e * e;

        double ya = y3 - 3 * y2 + 3 * y1 - y;
        double yb = 3 * (y2 - 2 * y1 + y);
        double yc = 3 * (y1 - y);
        double dy1 = ((ya * e + yb) * e + yc) * e;
        double dy3 = 6 * ya * e * e * e;
        double dy2 = dy3 + 2 * yb * e * e;

        for (int i = 2; i < nSeg; i++)
        {
            x += dx1; dx1 += dx2; dx2 += dx3;
            y += dy1; dy1 += dy2; dy2 += dy3;
            transformedVertex(x, y);
        }

        transformedVertex(x + dx1, y + dy1);
    }

    transformedVertex(x3, y3);
}

unittest
{
    // curve(): pure vertex-path bookkeeping, no display needed.
    // Identity matrix in effect (loadIdentity(), so the test is
    // order-independent regardless of what any other test leaves
    // currentMatrix_ set to) -- fl_transform_x/y() then collapse to the
    // identity, so the transformed start/end points equal the untransformed
    // ones exactly, matching FLTK's own documented curve endpoints
    // ("The curve ends... are at X0,Y0 and X3,Y3").
    loadIdentity();
    beginLine();
    curve(0, 0, 10, 40, 40, 40, 50, 0);
    assert(vertexPoints_.length >= 2);
    assert(vertexPoints_[0] == VPoint(0, 0));
    assert(vertexPoints_[$ - 1] == VPoint(50, 0));
    endLine(); // safe no-op without a live X display (gc_ is null)

    // A straight-line "curve" (control points collinear with the
    // endpoints) has zero enclosed area, so nSeg <= 1 and only the
    // start/end points are emitted -- exercises the early-return branch.
    beginLine();
    curve(0, 0, 5, 0, 10, 0, 20, 0);
    assert(vertexPoints_.length == 2);
    assert(vertexPoints_[0] == VPoint(0, 0));
    assert(vertexPoints_[$ - 1] == VPoint(20, 0));
    endLine();
}

// Every X-drawing call in this module's native (version(linux)) tails
// gates on `gc_ !is null && drawable_ != 0`, not `gc_ !is null` alone --
// this rule applies file-wide, not just to the vertex/transform-stack
// functions just below where it was first documented. `gc_` is created
// once, eagerly, the moment openDisplay() runs (a single shared GC bound
// to the root window purely to have *a* valid GC handle to use later
// against whatever real window setDrawable() eventually points it at)
// -- it does NOT mean a real target to draw into has been set up yet.
// `drawable_` is the thing that actually tracks that ("`Drawable.init`/0,
// X's `None`, until setDrawable() runs"). This matters in practice:
// `fl.core`'s clipboard tests (`copy()`/`paste()`) call openDisplay()
// directly from a headless `dub test` run whenever a real X server
// happens to be reachable (this port's own dev environment), which
// leaves `gc_` non-null but `drawable_` still 0 for the rest of that
// same test process -- any drawing call that only checks `gc_ !is
// null` risks an async `BadDrawable` X protocol error surfacing later,
// mid-test-run, from an unrelated synchronous round-trip elsewhere,
// once test execution order happens to call `openDisplay()` before any
// window is ever shown. This guard has to be universal across every leaf
// drawing call, not added function-by-function as each one happens to
// get exercised by a test order that reveals the gap.

version (linux)
{
    /// Converts VPoint[] to a real XPoint[] just before an Xlib call --
    /// the two structs are layout-identical (`short x, y`), but kept as
    /// distinct types so the path buffer above stays usable without
    /// `version(linux)` (see VPoint's own doc comment). Adds the current
    /// `offsetX_`/`offsetY_` -- this is the
    /// single funnel every vertex-path end_*() function (`endPolygon()`/
    /// `endLoop()`/`drawLineStrip()`/`endPoints()`/
    /// `endComplexPolygon()`) converts its accumulated points
    /// through right before the actual Xlib call, so adding the offset
    /// here covers that whole family in one place rather than needing a
    /// separate `+offsetX_`/`+offsetY_` at each of their five call sites.
    private XPoint[] toXPoints(VPoint[] pts)
    {
        XPoint[] xpts;
        xpts.length = pts.length;
        foreach (i, p; pts) xpts[i] = XPoint(cast(short)(p.x + offsetX_), cast(short)(p.y + offsetY_));
        return xpts;
    }
}

/// Converts VPoint[] to `fl.graphics_driver.Point[]` for a dispatched
/// end_*() call -- the driver-facing counterpart to toXPoints() above,
/// usable on every platform since Point itself is.
private Point[] toDriverPoints(const(VPoint)[] pts)
{
    Point[] result;
    result.length = pts.length;
    foreach (i, p; pts) result[i] = Point(p.x, p.y);
    return result;
}

/// Ends the path started by beginPolygon(), drawing it filled.
/// Dispatches to `fl.graphics_driver.currentDriver` first when one is
/// active; otherwise real on Linux, ported from Fl_Xlib_Graphics_
/// Driver::end_polygon(): drops a trailing point equal to the first
/// (fixloop(), an already-closed loop needs no help from XFillPolygon,
/// which closes it implicitly), then fills via XFillPolygon() with the
/// `Convex` shape hint FLTK uses for this call (every shape
/// fl.dial/fl.clock draw this way -- triangular hands, rectangular
/// ticks, the circle-approximating 32-gon above -- genuinely is
/// convex). Fewer than 3 points draws nothing on *any* backend (matches
/// FLTK: a filled "polygon" can't exist below a triangle -- this
/// port doesn't port the end_line()/end_points() fallback FLTK's
/// driver base class would take instead, since fl.dial/fl.clock never
/// hit it).
void endPolygon()
{
    if (vertexKind_ != VertexKind.polygon) return;
    vertexKind_ = VertexKind.none;
    auto pts = fixloop(vertexPoints_);
    if (pts.length <= 2) return;
    if (currentDriver !is null)
    {
        currentDriver.endPolygon(toDriverPoints(pts));
        return;
    }
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0)
        {
            XPoint[] xpts = toXPoints(pts);
            XFillPolygon(display_, drawable_, gc_, xpts.ptr, cast(int) xpts.length,
                polygonShapeConvex, coordModeOrigin);
        }
    }
}

/// Ends the path started by beginLoop(), drawing it as an outline.
/// Dispatches to `fl.graphics_driver.currentDriver` first when one is
/// active (see `GraphicsDriver.endLoop()`'s own doc comment for why
/// this gets a real dispatch hook despite FLTK's own SVG driver
/// skipping it); otherwise real on Linux, ported from Fl_Xlib_Graphics_
/// Driver::end_loop(): closes the loop by re-appending the first point
/// (after fixloop() strips any trailing duplicate of it), then strokes
/// via XDrawLines() -- unlike endPolygon(), this always draws (even
/// a 2-point "loop" is a valid degenerate line), matching FLTK's
/// unconditional end_line() call.
void endLoop()
{
    if (vertexKind_ != VertexKind.loop) return;
    vertexKind_ = VertexKind.none;
    VPoint[] pts = fixloop(vertexPoints_).dup;
    if (pts.length > 2) pts ~= pts[0];
    if (pts.length <= 1) return;
    if (currentDriver !is null)
    {
        currentDriver.endLoop(toDriverPoints(pts));
        return;
    }
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0)
        {
            XPoint[] xpts = toXPoints(pts);
            drawLinesScaled(xpts);
        }
    }
}

version (linux)
{
    /**
     * Draws a polyline (`XDrawLines()`) with its line *thickness* scaled
     * proportionally, not just its vertex positions -- shared by
     * `endLoop()` and `drawLineStrip()`. A plain `XDrawLines()` always
     * draws exactly 1 device pixel thick regardless of `scale()`, same
     * underlying issue `fl_xyline()`/`fl_yxline()`'s own doc comment
     * describes for axis-aligned lines, just for arbitrary (including
     * diagonal) polygon outlines here: without this, a "gtk+"-scheme box's corner-cut
     * octagonal outline (`beginLoop()`/`vertex()`/`endLoop()`, not
     * `fl_xyline()`/`fl_yxline()`) would
     * leave a 1-device-pixel gap between itself and the adjacent
     * gradient line drawn 1 logical unit further in, at any scale other
     * than 1.
     *
     * Unlike the axis-aligned case, an arbitrary polyline segment can't
     * simply be redrawn as a filled rectangle -- a diagonal segment has
     * no single "thickness" axis to widen along. Matches FLTK's own
     * real fix for the equivalent case
     * (`Fl_Scalable_Graphics_Driver::xyline()`'s pen-width-widening
     * dance) far more literally here than `fl_xyline()`/`fl_yxline()`
     * could: temporarily widen the GC's own line width to
     * `int(currentScale())` via `XSetLineAttributes()`, draw, then reset
     * it back to 0 (this port's own established "no persistent line-
     * width state, callers restore it themselves" contract -- see this
     * module's "General line style" section comment -- makes 0 a safe
     * assumption for the width already in effect on entry). Only
     * widens the default hairline pen: after a `lineStyle()` call that set a
     * style, width or dashes (`penCustom_`) the path is drawn with that pen
     * as set, already scaled by `lineStyle()`. Only
     * widens for a whole-number scale (`s == s_int`); a fractional scale
     * would need FLTK's own further `lwidth`-based centering
     * dance this port's line-style state deliberately doesn't carry,
     * so a fractional-scale outline stays a 1-device-pixel line, same
     * residual gap as before -- a smaller, still-open gap, not
     * regressed by this fix.
     */
    private void drawLinesScaled(XPoint[] xpts)
    {
        float s = currentScale();
        int sInt = cast(int) s;
        bool widen = !penCustom_ && sInt >= 2 && s == sInt;
        if (widen) XSetLineAttributes(display_, gc_, cast(uint) sInt, LineSolid, CapButt, JoinMiter);
        XDrawLines(display_, drawable_, gc_, xpts.ptr, cast(int) xpts.length, coordModeOrigin);
        if (widen) XSetLineAttributes(display_, gc_, 0, LineSolid, CapButt, JoinMiter);
    }
}

/// Shared dispatch/XDrawLines() call behind endLine() and
/// endComplexPolygon()'s too-few-points fallback -- no fixloop()
/// (an open polyline/fallback isn't a closed shape). Matches FLTK's
/// own sharing: `Fl_Graphics_Driver::end_complex_polygon()`'s fallback
/// calls `end_line()` as a real virtual method, so whatever driver is
/// current handles both callers through the same override -- this port
/// gets the same effect by having both callers share this one function.
private void drawLineStrip(VPoint[] pts)
{
    if (pts.length <= 1) return;
    if (currentDriver !is null)
    {
        currentDriver.endLine(toDriverPoints(pts));
        return;
    }
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0)
        {
            XPoint[] xpts = toXPoints(pts);
            drawLinesScaled(xpts);
        }
    }
}

/// Ends the path started by beginPoints(), drawing disconnected
/// pixels. Dispatches to `fl.graphics_driver.currentDriver` first when
/// one is active; otherwise real on Linux (XDrawPoints), ported from
/// Fl_Xlib_Graphics_Driver::end_points(): `if (n>1)` is FLTK's own
/// condition, not this port's -- a single-point path draws nothing
/// through this call on *any* backend (see FLTK_ISSUES.md's
/// candidate entry for the full reasoning), ported faithfully rather
/// than silently fixed.
void endPoints()
{
    if (vertexKind_ != VertexKind.points) return;
    vertexKind_ = VertexKind.none;
    if (vertexPoints_.length <= 1) return;
    if (currentDriver !is null)
    {
        currentDriver.endPoints(toDriverPoints(vertexPoints_));
        return;
    }
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0)
        {
            XPoint[] xpts = toXPoints(vertexPoints_);
            XDrawPoints(display_, drawable_, gc_, xpts.ptr, cast(int) xpts.length,
                coordModeOrigin);
        }
    }
}

/// Ends the path started by beginLine(), drawing an open polyline.
/// Ported from Fl_Xlib_Graphics_Driver::end_line(): FLTK's own `if
/// (n<2) { end_points(); return; }` fallback is skipped here as dead
/// code, not an omission -- at n<2, end_points() itself also requires
/// n>1 to draw anything (see endPoints()'s own doc comment), so
/// that fallback can never actually produce a visible point either;
/// drawLineStrip()'s own `pts.length > 1` guard already covers every
/// case this path can reach, on every backend.
void endLine()
{
    if (vertexKind_ != VertexKind.line) return;
    vertexKind_ = VertexKind.none;
    drawLineStrip(vertexPoints_);
}

/// Ends the path started by beginComplexPolygon(), drawing it
/// filled. Ported from Fl_Xlib_Graphics_Driver::end_complex_polygon():
/// calls fl_gap() first (closing the final sub-loop), then falls back
/// to drawLineStrip() (matching FLTK's own end_line() fallback,
/// including its dispatch -- see that function's own doc comment) if
/// fewer than 3 points resulted; otherwise dispatches to
/// `fl.graphics_driver.currentDriver` first when one is active, else
/// real on Linux, filling via XFillPolygon() with the `Complex` shape
/// hint (0, not polygonShapeConvex -- unlike endPolygon(), a
/// complex polygon may genuinely be concave/multi-loop, so the server
/// can't assume convexity).
void endComplexPolygon()
{
    if (vertexKind_ != VertexKind.complexPolygon) return;
    fl_gap();
    vertexKind_ = VertexKind.none;
    if (vertexPoints_.length < 3)
    {
        drawLineStrip(vertexPoints_);
        return;
    }
    if (currentDriver !is null)
    {
        currentDriver.endComplexPolygonParts(toDriverPoints(vertexPoints_), gapCounts_);
        return;
    }
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0)
        {
            XPoint[] xpts = toXPoints(vertexPoints_);
            XFillPolygon(display_, drawable_, gc_, xpts.ptr, cast(int) xpts.length,
                polygonShapeComplex, coordModeOrigin);
        }
    }
}

unittest
{
    // fl_gap(): pure vertex-path bookkeeping, no display needed --
    // exercises all three branches documented on fl_gap()'s own comment.
    // loadIdentity() first so vertex()'s raw coordinates below
    // pass straight through regardless of what any other test leaves
    // currentMatrix_ set to (same reasoning as the curve() test above).
    loadIdentity();

    // Branch 1 (truncate then close-and-advance): a triangle whose last
    // vertex duplicates its own first vertex (caller closed it by hand)
    // gets that duplicate dropped, then re-closed by fl_gap() itself,
    // leaving exactly 4 points (3 unique + the closing repeat) and
    // gapIndex_ advanced past them.
    beginComplexPolygon();
    vertex(0, 0);
    vertex(10, 0);
    vertex(5, 10);
    vertex(0, 0); // caller-closed duplicate of the start point
    fl_gap();
    assert(vertexPoints_.length == 4);
    assert(vertexPoints_[0] == VPoint(0, 0));
    assert(vertexPoints_[$ - 1] == VPoint(0, 0));
    assert(gapIndex_ == 4);

    // A second sub-loop (a hole), same shape, appended after the gap --
    // endComplexPolygon() calls fl_gap() once more internally to
    // close this one too.
    vertex(2, 2);
    vertex(6, 2);
    vertex(4, 6);
    endComplexPolygon(); // safe no-op draw without a live X display
    assert(vertexPoints_.length == 8); // 4 (first loop) + 3 + 1 closing repeat

    // Branch 2 (discard degenerate sub-loop): fewer than 3 unique points
    // since the last gap -- fl_gap() truncates back to gapIndex_ instead
    // of closing it.
    beginComplexPolygon();
    vertex(0, 0);
    vertex(10, 0);
    vertex(5, 10);
    fl_gap(); // closes the first (real) sub-loop: 3 -> 4 points, gapIndex_ = 4
    assert(vertexPoints_.length == 4);
    assert(gapIndex_ == 4);
    vertex(1, 1); // a single stray point -- not enough for a second loop
    fl_gap();
    assert(vertexPoints_.length == 4); // the stray point was discarded
    assert(gapIndex_ == 4);
    endComplexPolygon();

    // Branch 3 (harmless no-op call): fl_gap() before any vertex at all.
    beginComplexPolygon();
    fl_gap();
    assert(vertexPoints_.length == 0);
    endComplexPolygon();
}

unittest
{
    // Regression test for a double-scaling bug (`source/test/arc.d`'s
    // donut shape: correct at
    // scale 1.0 -- where double-scaling happens to be a no-op -- but
    // spikes sticking out at any other scale). The test
    // above already covers `fl_gap()`'s branching at the *default*
    // scale, which is exactly why it never caught this: re-scaling an
    // already-scaled point by 1.0 changes nothing. Re-run the same
    // "closing point" shape at scale 2.0: a nonzero start point is
    // needed to actually distinguish "scaled once" from "scaled twice"
    // ((0,0) scaled any number of times is still (0,0)).
    scope (exit) currentScale(1.0f); // don't leak into other tests
    loadIdentity();
    currentScale(2.0f);

    beginComplexPolygon();
    vertex(3, 4);
    vertex(13, 4);
    vertex(8, 14);
    fl_gap();
    assert(vertexPoints_[0] == VPoint(6, 8));  // (3,4) * 2.0
    assert(vertexPoints_[1] == VPoint(26, 8)); // (13,4) * 2.0
    assert(vertexPoints_[2] == VPoint(16, 28)); // (8,14) * 2.0
    // The closing point must be (3,4) * 2.0 == (6,8), scaled once --
    // not (3,4) * 2.0 * 2.0 == (12,16), the real bug's actual output.
    assert(vertexPoints_[$ - 1] == VPoint(6, 8));
    endComplexPolygon();
}

/// Drops trailing points equal to pts[0] -- FLTK's fixloop(), shared
/// by endPolygon()/endLoop() so a path a caller already closed
/// by hand (ending vertex() on the same point it started) doesn't
/// get a redundant/degenerate closing segment.
private VPoint[] fixloop(VPoint[] pts)
{
    size_t n = pts.length;
    while (n > 2 && pts[n - 1].x == pts[0].x && pts[n - 1].y == pts[0].y) n--;
    return pts[0 .. n];
}

/**
 * Returns the weighted average of c1 and c2: `color1 * weight + color2
 * * (1 - weight)` per channel (weight 1.0 = all c1, 0.0 = all c2).
 * Ported from src/fl_color.cxx's fl_color_average() -- real since
 * colorToRgb8()/rgbColor() exist to decode/repack both "free"
 * (packed-RGB) and indexed colors.
 */
Color colorAverage(Color c1, Color c2, float weight)
{
    ubyte r1, g1, b1, r2, g2, b2;
    colorToRgb8(c1, r1, g1, b1);
    colorToRgb8(c2, r2, g2, b2);
    ubyte r = cast(ubyte)(r1 * weight + r2 * (1 - weight));
    ubyte g = cast(ubyte)(g1 * weight + g2 * (1 - weight));
    ubyte b = cast(ubyte)(b1 * weight + b2 * (1 - weight));
    return rgbColor(r, g, b);
}

/// Returns the inactive (dimmed/grayed-out) variant of c, used to draw
/// disabled widgets. Ported from src/fl_color.cxx's fl_inactive():
/// `colorAverage(c, FL_GRAY, .33f)`.
Color inactive(Color c)
{
    return colorAverage(c, gray, .33f);
}

/// Physical (linear-light) luminance Y of c, range 0.0 (black) to 1.0
/// (white). Ported from `src/fl_contrast.cxx`'s `fl_luminance()`: the
/// standard Rec. 709/sRGB relative-luminance weights applied to a
/// `pow(x, 2.4)`-gamma-corrected version of each sRGB channel
/// (matching FLTK's own simplified gamma exactly, not the real
/// piecewise sRGB EOTF). **Not perceptually linear on its own** -- see
/// `lightness()` below for the value that actually is.
double luminance(Color c)
{
    import std.math : pow;

    ubyte r, g, b;
    colorToRgb8(c, r, g, b);
    return 0.2126729 * pow(r / 255.0, 2.4)
        + 0.7151522 * pow(g / 255.0, 2.4)
        + 0.0721750 * pow(b / 255.0, 2.4);
}

/// Perceived lightness L* of c, per the CIELAB (L*a*b*) color model --
/// almost linear with respect to human visual perception, unlike raw
/// luminance. Range 0 (black) to 100 (white); two results can be
/// compared directly, and their difference is the perceived contrast.
/// Ported from `src/fl_contrast.cxx`'s `fl_lightness()`.
double lightness(Color c)
{
    import std.math : pow;

    double y = luminance(c);
    if (y <= 216.0 / 24389.0) return y * (24389.0 / 27.0);
    return pow(y, 1.0 / 3.0) * 116.0 - 16.0;
}

// ---------------------------------------------------------------------
// contrastMode()/contrastLevel()/contrastFunction(): the
// runtime switch between the CIELAB (default) and legacy contrast
// algorithms, plus a caller-registered custom one. Ported from
// `src/fl_contrast.cxx`'s matching module-static state.
// ---------------------------------------------------------------------

private ContrastMode contrastMode_ = ContrastMode.contrastCielab;

/// One stored level per mode, index-matched to `ContrastMode`'s own
/// values -- matching FLTK's `fl_contrast_level_[10]` (only the
/// first 4 slots are ever addressed; FLTK's extra headroom for
/// "4-9 = not yet defined" isn't needed here since `ContrastMode` has
/// no unused trailing members to index past `contrastCustom`).
private int[4] contrastLevel_ = [0, 50, 39, 0];

private ContrastFunction contrastFunction_;

/**
 * Sets the contrast algorithm `contrast()` uses. An invalid `mode`
 * (including `ContrastMode.contrastLast`) falls back to
 * `contrastCielab`, matching FLTK's own guard. Ported from
 * `contrastMode(int)`.
 */
void contrastMode(ContrastMode mode)
{
    contrastMode_ = (mode >= 0 && mode < ContrastMode.contrastLast)
        ? mode : ContrastMode.contrastCielab;
}

/// Returns the current contrast algorithm. Ported from `fl_contrast_mode()`.
ContrastMode contrastMode()
{
    return contrastMode_;
}

/**
 * Sets the contrast sensitivity (0-100, clamped) of the *current*
 * mode's algorithm -- each mode stores its own level independently, so
 * `contrastMode()` must be set first if targeting a mode other than
 * the current one. Ported from `fl_contrast_level(int)`.
 */
void contrastLevel(int level)
{
    if (level < 0) level = 0;
    else if (level > 100) level = 100;
    contrastLevel_[contrastMode_] = level;
}

/// Returns the current mode's contrast sensitivity. Ported from
/// `contrastLevel()`.
int contrastLevel()
{
    return contrastLevel_[contrastMode_];
}

/**
 * Registers the function `contrast()` calls while in
 * `ContrastMode.contrastCustom` -- has no effect in any other mode.
 * Ported from `fl_contrast_function(Fl_Contrast_Function*)`; see
 * `ContrastFunction`'s own doc comment (`fl.enumerations`) for why this
 * takes a D delegate rather than FLTK's bare function pointer.
 */
void contrastFunction(ContrastFunction f)
{
    contrastFunction_ = f;
}

/**
 * Returns fg if it already contrasts enough against bg to stay
 * legible, otherwise plain black or white (whichever contrasts more
 * with bg). Dispatches on `contrastMode()` -- `contrastCielab`
 * (FLTK's real default since FLTK 1.4.0, perceptual contrast in
 * CIELAB color space via `lightness()` above) unless
 * `contrastLegacy()`/`contrastCustom` is selected. `context`/`size` are
 * currently unused by either built-in algorithm (matching FLTK's
 * own "defined for future extensions" note) but are passed through to
 * a registered custom function. Ported from `src/fl_contrast.cxx`'s
 * `contrast()`/`fl_contrast_cielab()`.
 *
 * The older, FLTK-1.3.x-
 * compatible algorithm is still available -- see `contrastLegacy()` below, kept around
 * matching FLTK's own choice to keep its `static
 * fl_contrast_legacy()` alongside the new default.
 *
 * The mode/level/custom-function switch is real too, routed through `contrastMode_`/`contrastLevel_`/`contrastFunction_`
 * above, matching FLTK's `fl_contrast_mode()`/`fl_contrast_level()`/
 * `contrastFunction()` exactly.
 */
Color contrast(Color fg, Color bg, int context = 0, int size = 0)
{
    final switch (contrastMode_)
    {
    case ContrastMode.contrastNone:
        return fg;

    case ContrastMode.contrastLegacy:
        return contrastLegacy(fg, bg, context, size);

    case ContrastMode.contrastCustom:
        if (contrastFunction_ !is null)
            return contrastFunction_(fg, bg, context, size);
        goto case ContrastMode.contrastCielab; // FALLTHROUGH, matching FLTK

    case ContrastMode.contrastCielab:
    case ContrastMode.contrastLast: // unreachable via fl_contrast_mode()'s own guard
        double tc = cast(double) contrastLevel_[ContrastMode.contrastCielab];
        enum tbw = 50.0; // black/white threshold (the perceptual midpoint)

        double lfg = lightness(fg);
        double lbg = lightness(bg);
        double lc = lfg - lbg;

        if (lc >= tc || lc <= -tc) return fg; // sufficient contrast already
        return lbg > tbw ? black : white;     // light background -> black; dark -> white
    }
}

/// ditto, the older FLTK-1.3.x-compatible algorithm (integer
/// luminance difference against two fixed thresholds, scaled by the
/// legacy mode's own stored `fl_contrast_level()`). Ported from
/// `fl_contrast_legacy()` (`static`, FLTK's own doc comment: "Do
/// not change this except for level adjustment"); FLTK's own
/// comment on the luminance formula: "FLTK 1.3 compatible, don't change
/// this!" `context`/`size` are accepted (and ignored, matching
/// FLTK) purely so `contrast()`'s dispatch above can call this
/// and a registered custom function through the same shape.
Color contrastLegacy(Color fg, Color bg, int context = 0, int size = 0)
{
    ubyte fgR, fgG, fgB, bgR, bgG, bgB;
    colorToRgb8(fg, fgR, fgG, fgB);
    colorToRgb8(bg, bgR, bgG, bgB);

    int lfg = (fgR * 30 + fgG * 59 + fgB * 11) / 100;
    int lbg = (bgR * 30 + bgG * 59 + bgB * 11) / 100;
    int lc = lfg - lbg;

    int level = contrastLevel_[ContrastMode.contrastLegacy];
    int tc;
    if (level == 100) tc = 256;
    else if (level == 0) tc = 0;
    else if (level > 50) tc = 99 + (level - 50) * (255 - 99) / 50;
    else tc = 99 - (50 - level) * 99 / 50;
    enum tbw = 127; // black/white threshold (127 <=> 49.80%)

    if (lc > tc || lc < -tc) return fg; // sufficient contrast already
    return lbg > tbw ? black : white;   // light background -> black; dark -> white
}

/**
 * Geometry for drawCheck()'s six-vertex checkmark polygon --
 * ported verbatim from src/fl_draw.cxx's fl_draw_check() (the size-
 * fitting arithmetic before the `beginComplexPolygon()` block).
 * Split out as pure, platform-independent geometry (unlike FLTK,
 * which interleaves it with the actual drawing calls) so it doesn't
 * need to live inside a version(linux) block -- only the six-vertex
 * fill below does.
 */
private struct CheckPoints { int x0, y0, x1, y1, x2, y2, x3, y3, x4, y4, x5, y5; }

private CheckPoints computeCheckPoints(Rect bb)
{
    enum int md = 6; // max. d1 value: 3 * md + 1 pixels wide
    int tx = bb.x();
    int ty = bb.y();
    int tw = bb.w();
    int th = bb.h();
    int lh = 3; // line height 3 means 4 pixels
    int d1, d2;

    // make sure there's a free 1-pixel border if the area is large enough
    if (tw > 10) { tx++; tw -= 2; }
    if (th > 10) { ty++; th -= 2; }

    // d1/d2: width/height of the left/right parts of the check mark
    d1 = tw / 3;
    d2 = 2 * d1;
    if (d1 > md) { d1 = md; d2 = 2 * d1; }
    if (d2 + lh + 1 > th) { d2 = th - lh - 1; d1 = (d2 + 1) / 2; } // make sure the height fits
    if (d1 < 2) { d1 = 2; d2 = 4; } // box too small: clamp to a minimal size
    if (d1 < 3) lh = 2; // reduce line height (width) for small sizes

    tw = d1 + d2 + 1; // total width
    th = d2 + lh + 1; // total height

    tx = bb.x() + (bb.w() - tw + 1) / 2; // x position (centered)
    ty = bb.y() + (bb.h() - th + 1) / 2; // y position (centered)

    CheckPoints p;
    ty += d2 - d1; // upper border of check mark: left to right
    p.x0 = tx;          p.y0 = ty;
    p.x1 = tx + d1;      p.y1 = ty + d1;
    p.x2 = tx + d1 + d2; p.y2 = ty + d1 - d2;
    ty += lh; // lower border of check mark: right to left
    p.x3 = tx + d1 + d2; p.y3 = ty + d1 - d2;
    p.x4 = tx + d1;      p.y4 = ty + d1;
    p.x5 = tx;           p.y5 = ty;
    return p;
}

version (linux)
{
    /// Draws a checkmark filling bb, in color col (fl_color() is
    /// preserved across the call, matching FLTK). Real on Linux
    /// (XFillPolygon, the same "Complex" shape this port's fl_polygon()
    /// already uses -- needed here since the checkmark is a genuinely
    /// concave hexagon, not decomposable into the 3-/4-point convex
    /// shapes fl_polygon() supports). Drawn directly against XFillPolygon
    /// rather than through the transform-stack beginComplexPolygon()/
    /// vertex()/endComplexPolygon() API FLTK uses (real in
    /// this port too now, see the "complex drawing" section above -- but
    /// would add nothing here anyway, since this shape never needs
    /// rotation/scaling). Each point scaled via `scaledFloor()` before
    /// the offset is added, same order every other primitive in this
    /// module uses.
    void drawCheck(Rect bb, Color col)
    {
        if (gc_ is null || drawable_ == 0) return;
        auto p = computeCheckPoints(bb);
        XPoint[6] pts = [
            XPoint(cast(short)(scaledFloor(p.x0) + offsetX_), cast(short)(scaledFloor(p.y0) + offsetY_)),
            XPoint(cast(short)(scaledFloor(p.x1) + offsetX_), cast(short)(scaledFloor(p.y1) + offsetY_)),
            XPoint(cast(short)(scaledFloor(p.x2) + offsetX_), cast(short)(scaledFloor(p.y2) + offsetY_)),
            XPoint(cast(short)(scaledFloor(p.x3) + offsetX_), cast(short)(scaledFloor(p.y3) + offsetY_)),
            XPoint(cast(short)(scaledFloor(p.x4) + offsetX_), cast(short)(scaledFloor(p.y4) + offsetY_)),
            XPoint(cast(short)(scaledFloor(p.x5) + offsetX_), cast(short)(scaledFloor(p.y5) + offsetY_)),
        ];
        Color old = fl_color();
        fl_color(col);
        XFillPolygon(display_, drawable_, gc_, pts.ptr, cast(int) pts.length,
            polygonShapeComplex, coordModeOrigin);
        fl_color(old);
    }
}
else version (Windows)
{
    import core.sys.windows.windows;
    import fl.gdi_graphics_driver : GdiGraphicsDriver;

    /// Draws a checkmark filling bb, in color col -- the Windows
    /// counterpart of the Linux `XFillPolygon()` body above, via GDI's
    /// own native concave-polygon fill (`Polygon()`; GDI's default
    /// `ALTERNATE` fill mode already produces the correct result for
    /// this non-self-intersecting hexagon, so no `SetPolyFillMode()`
    /// call is needed, matching X11's `Complex`/default-winding fill
    /// for the same shape). This is the one shape in this
    /// module drawn via a direct Xlib call that needs its own explicit
    /// Windows counterpart -- `drawRadio()` right below is built
    /// entirely from already-cross-platform-dispatched leaves
    /// (`fl_pie()`/`fl_rectf()`), so it needs no special-casing at all.
    /// `fl_color()` is preserved
    /// across the call, matching FLTK and the Linux body above.
    void drawCheck(Rect bb, Color col)
    {
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        if (driver is null || driver.hdc() is null) return;
        auto p = computeCheckPoints(bb);
        POINT[6] pts = [
            POINT(scaledFloor(p.x0) + offsetX_, scaledFloor(p.y0) + offsetY_),
            POINT(scaledFloor(p.x1) + offsetX_, scaledFloor(p.y1) + offsetY_),
            POINT(scaledFloor(p.x2) + offsetX_, scaledFloor(p.y2) + offsetY_),
            POINT(scaledFloor(p.x3) + offsetX_, scaledFloor(p.y3) + offsetY_),
            POINT(scaledFloor(p.x4) + offsetX_, scaledFloor(p.y4) + offsetY_),
            POINT(scaledFloor(p.x5) + offsetX_, scaledFloor(p.y5) + offsetY_),
        ];
        Color old = fl_color();
        fl_color(col);
        HGDIOBJ oldBrush = SelectObject(driver.hdc(), driver.brushAction(false));
        Polygon(driver.hdc(), pts.ptr, cast(int) pts.length);
        SelectObject(driver.hdc(), oldBrush);
        fl_color(old);
    }
}
else
{
    /// Fallback for platforms without a backend: draws a checkmark filling bb, forwarding to the graphics
    /// driver FLTK. No-op on unsupported platforms.
    void drawCheck(Rect bb, Color col)
    {
    }
}

/**
 * Draws a filled circle (radio button dot) of diameter d at (x,y).
 * Ported from src/fl_draw.cxx's fl_draw_radio(). The real "gtk+" scheme
 * branch (`fl.core.isScheme()`): a lighter highlight ring (an inner near-white disc plus a
 * partial highlight arc), reachable once the user
 * activates the "gtk+" scheme (`fl.core.scheme("gtk+")`) -- a
 * self-contained addition to this
 * one function, not a boxtype. fl_color() is preserved across the
 * call, matching FLTK.
 */
void drawRadio(int x, int y, int d, Color color)
{
    Color old = fl_color();
    if (fl.core.isScheme("gtk+"))
    {
        fl_color(color);
        fl_pie(x, y, d, d, 0.0, 360.0);
        Color icol = colorAverage(white, color, 0.2f);
        drawCircle(x + 2, y + 2, d - 4, icol);
        fl_color(colorAverage(white, color, 0.5f));
        fl_arc(x + 1, y + 1, d - 1, d - 1, 60.0, 180.0);
    }
    else
    {
        drawCircle(x + 1, y + 1, d - 2, color);
    }
    fl_color(old);
}

/**
 * Computes the applicable arrow size for a single arrow pointing o
 * within bb, drawn num-up (num == 2 for fl_draw_arrow_double()'s pair).
 * Ported from src/fl_draw_arrow.cxx's arrow_size(): the arrow's "width"
 * (along the direction it points) is bb's size on the pointing axis
 * divided by num, its "height" (across that axis) is half of bb's size
 * on the other axis, whichever's smaller wins, clamped to [2, 6].
 */
private int arrowSize(Rect bb, Orientation o, int num = 1)
{
    int d1, d2;
    if (o == Orientation.orientLeft || o == Orientation.orientRight)
    {
        d1 = (bb.w() - 2) / num;
        d2 = (bb.h() - 2) / 2;
    }
    else
    {
        d1 = (bb.h() - 2) / num;
        d2 = (bb.w() - 2) / 2;
    }
    int s = d1 < d2 ? d1 : d2;
    if (s < 2) s = 2;
    else if (s > 6) s = 6;
    return s;
}

/**
 * Draws a single triangular arrow of "radius" d (arrowSize(bb, o) if
 * negative) pointing o within bb, in color col. Ported from
 * src/fl_draw_arrow.cxx's fl_draw_arrow_single(): DELIBERATE
 * SIMPLIFICATION -- FLTK's own `gtk_chevron` bool is hardcoded
 * `false` (its `Fl::is_scheme("gtk+")` alternative is dead code, left
 * commented out FLTK after GitHub issue #1117 reverted "chevron
 * style" arrows), so only the plain triangle branches (a single
 * 3-point fl_polygon() call per direction) are ported; the chevron
 * (4-point) branches FLTK never actually reaches are skipped.
 * Returns false for an orientation this arrow style doesn't handle
 * (orientNone -- only fl_draw_arrow_choice() draws that one, via a
 * plain down arrow), matching FLTK's `int` success/failure return.
 */
private bool drawArrowSingle(Rect bb, Orientation o, Color col, int d = -1)
{
    int x1 = bb.x();
    int y1 = bb.y();
    if (d < 0) d = arrowSize(bb, o);

    fl_color(col);

    switch (o)
    {
    case Orientation.orientLeft:
        x1 += (bb.w() - d) / 2 - 1;
        y1 += bb.h() / 2;
        fl_polygon(x1, y1, x1 + d, y1 - d, x1 + d, y1 + d);
        return true;

    case Orientation.orientRight:
        x1 += (bb.w() - d) / 2;
        y1 += bb.h() / 2;
        fl_polygon(x1, y1 - d, x1, y1 + d, x1 + d, y1);
        return true;

    case Orientation.orientUp:
        x1 += bb.w() / 2;
        y1 += (bb.h() - d) / 2 - 1;
        fl_polygon(x1, y1, x1 + d, y1 + d, x1 - d, y1 + d);
        return true;

    case Orientation.orientDown:
        x1 += bb.w() / 2 - d;
        y1 += (bb.h() - d) / 2;
        fl_polygon(x1, y1, x1 + d, y1 + d, x1 + 2 * d, y1);
        return true;

    default:
        return false;
    }
}

/// Draws two arrows pointing o, side by side within bb, in color col.
/// Ported from src/fl_draw_arrow.cxx's fl_draw_arrow_double() --
/// straightforward, no scheme dependency to simplify away.
private bool drawArrowDouble(Rect bb, Orientation o, Color col)
{
    int d = arrowSize(bb, o, 2);
    int x1 = bb.x();
    int y1 = bb.y();
    int da = (d + 1) / 2;
    auto r = bb;

    switch (o)
    {
    case Orientation.orientLeft:
    case Orientation.orientRight:
        r.x(x1 - da);
        drawArrowSingle(r, o, col, d);
        r.x(x1 + da);
        return drawArrowSingle(r, o, col, d);

    case Orientation.orientUp:
    case Orientation.orientDown:
        r.y(y1 - da);
        drawArrowSingle(r, o, col, d);
        r.y(y1 + da);
        return drawArrowSingle(r, o, col, d);

    default:
        return false;
    }
}

/// Draws the arrow used by a Choice-like dropdown indicator, in color
/// col. Ported from src/fl_draw_arrow.cxx's fl_draw_arrow_choice(). Real
/// "gtk+"/"gleam" (small double-arrow) and "plastic" (larger double-
/// arrow) scheme branches (`fl.core.isScheme()`), reachable once the
/// user activates one of those schemes; the default/"none" branch (a
/// single plain down arrow) still applies otherwise. FLTK's own
/// gtk+/gleam branch shadows its outer w1/x1/y1 with its own local
/// x1/y1 (computed differently, only the plastic branch uses the outer
/// ones) -- renamed to sx/sy here since D doesn't allow shadowing, no
/// behavior change.
private bool drawArrowChoice(Rect bb, Color col)
{
    int w1 = (bb.w() - 4) / 3;
    if (w1 < 1) w1 = 1;
    int x1 = bb.x() + (bb.w() - 2 * w1 - 1) / 2;
    int y1 = bb.y() + (bb.h() - w1 - 1) / 2;

    if (fl.core.isScheme("gtk+") || fl.core.isScheme("gleam"))
    {
        int sx = bb.x() + (bb.w() - 6) / 2;
        int sy = bb.y() + bb.h() / 2;
        fl_color(col);
        fl_polygon(sx, sy - 2, sx + 3, sy - 5, sx + 6, sy - 2);
        fl_polygon(sx, sy + 2, sx + 3, sy + 5, sx + 6, sy + 2);
        return true;
    }
    else if (fl.core.isScheme("plastic"))
    {
        fl_color(col);
        fl_polygon(x1, y1 + 3, x1 + w1, y1 + w1 + 3, x1 + 2 * w1, y1 + 3);
        fl_polygon(x1, y1 + 1, x1 + w1, y1 - w1 + 1, x1 + 2 * w1, y1 + 1);
        return true;
    }
    else
    {
        return drawArrowSingle(bb, Orientation.orientDown, col);
    }
}

/**
 * Draws an "arrow-like" GUI element (t: arrowSingle/arrowDouble/
 * arrowChoice) pointing o, filling bb, in color color. Ported from
 * src/fl_draw_arrow.cxx's fl_draw_arrow() -- the shared entry point
 * behind Fl_Scrollbar's end-button arrows, Fl_Counter's increment/
 * decrement arrows, and (once ported) Fl_Choice/Fl_Menu_Button/
 * Fl_Spinner/Fl_Tabs's overflow indicators. The early
 * `Fl::is_scheme("oxy")` special case is real too (oxy_arrow()/
 * oxySingleArrow() defined in the "oxy"
 * scheme section below) -- it delegates entirely to a wholly separate
 * arrow-drawing implementation, matching FLTK's own structure
 * exactly, including FLTK's own asymmetry that this port
 * faithfully reproduces rather than "fixes": every other branch here
 * restores `fl_color(old)` on the way out, but FLTK's oxy branch
 * returns immediately after calling `oxy_arrow()` without restoring the
 * saved color at all (`src/fl_draw_arrow.cxx:242-289` -- the oxy
 * special case sits *before* the trailing `fl_color(saved_color)`, and
 * is the only path that `return`s early enough to skip it). Flagged as
 * an `FLTK_ISSUES.md` candidate rather than silently corrected.
 */
void drawArrow(Rect bb, ArrowType t, Orientation o, Color color)
{
    Color old = fl_color();

    if (fl.core.isScheme("oxy"))
    {
        oxyArrow(bb, t, o, color);
        return;
    }

    bool ok;
    switch (t)
    {
    case ArrowType.arrowSingle: ok = drawArrowSingle(bb, o, color); break;
    case ArrowType.arrowDouble: ok = drawArrowDouble(bb, o, color); break;
    case ArrowType.arrowChoice: ok = drawArrowChoice(bb, color); break;
    default: ok = false; break;
    }
    if (!ok)
    {
        // Error flag: a red rectangle with a black X through it,
        // matching FLTK's fallback for an orientation/type this
        // style doesn't handle.
        fl_color(red);
        fl_rectf(bb.x(), bb.y(), bb.w(), bb.h());
        fl_color(black);
        fl_rect(bb.x(), bb.y(), bb.w(), bb.h());
        fl_line(bb.x(), bb.y(), bb.r(), bb.b());
        fl_line(bb.x(), bb.b(), bb.r(), bb.y());
    }
    fl_color(old);
}

/// Draws a line from (x,y) to (x1,y1). Dispatches to
/// `fl.graphics_driver.currentDriver` first when one is active.
/// Ported from `Fl_Scalable_Graphics_Driver::line(x,y,x1,y1)`
/// (`src/Fl_Graphics_Driver.cxx`): an axis-aligned call (`y == y1` or
/// `x == x1`) redirects to `fl_xyline()`/`fl_yxline()` instead of
/// drawing here directly, so a horizontal/vertical line drawn through
/// this general entry point gets those functions' scale-proportional
/// thickness and corner-convergence handling for free, matching
/// FLTK exactly -- this covers
/// `fl.chart`'s gridlines, `fl.browser`'s separator lines,
/// `fl.help_view`'s horizontal rules, and the "oxy" scheme's own box
/// border, all of which draw axis-aligned lines through this function. Only a
/// genuinely diagonal line falls through to the plain
/// `scaledFloor()`-per-coordinate `XDrawLine()` path below, matching
/// FLTK's own `line_unscaled(floor(x),floor(y),floor(x1),floor(y1))`
/// fallback; no clipping in that native path (see
/// `Fl_Xlib_Graphics_Driver::line_unscaled()`, not fully ported).
void fl_line(int x, int y, int x1, int y1)
{
    if (currentDriver !is null)
    {
        currentDriver.line(x, y, x1, y1);
        return;
    }
    version (linux) { if (!penNeedsXDrawLine_) {
        if (y == y1) { fl_xyline(x, y, x1); return; }
        if (x == x1) { fl_yxline(x, y, y1); return; }
    } }
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0) XDrawLine(display_, drawable_, gc_,
            scaledFloor(x) + offsetX_, scaledFloor(y) + offsetY_,
            scaledFloor(x1) + offsetX_, scaledFloor(y1) + offsetY_);
    }
}

/// Draws two connected line segments: (x,y)-(x1,y1)-(x2,y2). Added for
/// fl.draw's own flDiamondUpBox()/flDiamondDownBox() (the diamond
/// boxtype's bevel lines).
///
/// Does NOT decompose into two 2-arg fl_line()
/// calls, unlike FLTK's own base
/// `Fl_Graphics_Driver::line(x,y,x1,y1,x2,y2)` (that's the *unscaled* base class).
/// The real scaled driver,
/// `Fl_Scalable_Graphics_Driver::line(x,y,x1,y1,x2,y2)`
/// (`src/Fl_Graphics_Driver.cxx`), does NOT decompose either -- it scales all
/// 6 coordinates once, uniformly, in a single pass. Decomposing would
/// let the two segments' shared midpoint (x1,y1) round two different
/// ways whenever one segment happened to be axis-aligned (redirected
/// through fl_xyline()'s/fl_yxline()'s own endpoint-extension fix
/// above) and the other diagonal (plain scaledFloor() per coordinate):
/// plasticFrameRect() (this module, further down) draws each side of
/// its chamfered-corner frame as one 3-point fl_line() call with
/// exactly this axis-aligned-then-diagonal shape, so plastic-scheme
/// buttons would pick up a 1-device-pixel notch at their corners the
/// moment fl_xyline()'s far endpoint stopped agreeing with a diagonal
/// XDrawLine()'s own per-coordinate floor of the identical value.
/// Driver dispatch is preserved via two `currentDriver.line()` calls
/// (matching FLTK's own undecomposed base-class behavior there,
/// since the graphics-driver abstraction has no 6-arg `line()` of its
/// own to call directly) -- only the native Xlib path was changed.
void fl_line(int x, int y, int x1, int y1, int x2, int y2)
{
    if (currentDriver !is null)
    {
        currentDriver.line(x, y, x1, y1);
        currentDriver.line(x1, y1, x2, y2);
        return;
    }
    version (linux)
    {
        int sx = scaledFloor(x), sy = scaledFloor(y);
        int sx1 = scaledFloor(x1), sy1 = scaledFloor(y1);
        int sx2 = scaledFloor(x2), sy2 = scaledFloor(y2);
        if (gc_ !is null && drawable_ != 0)
        {
            XDrawLine(display_, drawable_, gc_, sx + offsetX_, sy + offsetY_, sx1 + offsetX_, sy1 + offsetY_);
            XDrawLine(display_, drawable_, gc_, sx1 + offsetX_, sy1 + offsetY_, sx2 + offsetX_, sy2 + offsetY_);
        }
    }
}

/// Draws a closed, unfilled 3-point loop: (x0,y0)-(x1,y1)-(x2,y2)-
/// (x0,y0).
///
/// Does not decompose into three 2-arg fl_line() calls, which is what
/// FLTK's *unscaled* base `Fl_Graphics_Driver::loop()` does, because the
/// real scaled driver differs:
/// `Fl_Scalable_Graphics_Driver::loop(x0,y0,x1,y1,x2,y2)`
/// (`src/Fl_Graphics_Driver.cxx`) scales all 6 coordinates once,
/// uniformly, in a single pass, for exactly the same reason the 3-point
/// fl_line() fix above does: decomposing lets each shared vertex round
/// two different ways depending on whether the segment on either side
/// of it happens to be axis-aligned (redirected through fl_xyline()'s/
/// fl_yxline()'s own endpoint-extension) or diagonal (plain
/// scaledFloor() per coordinate).
void loop(int x0, int y0, int x1, int y1, int x2, int y2)
{
    if (currentDriver !is null)
    {
        currentDriver.loop(x0, y0, x1, y1, x2, y2);
        return;
    }
    int sx0 = scaledFloor(x0), sy0 = scaledFloor(y0);
    int sx1 = scaledFloor(x1), sy1 = scaledFloor(y1);
    int sx2 = scaledFloor(x2), sy2 = scaledFloor(y2);
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0)
        {
            XDrawLine(display_, drawable_, gc_, sx0 + offsetX_, sy0 + offsetY_, sx1 + offsetX_, sy1 + offsetY_);
            XDrawLine(display_, drawable_, gc_, sx1 + offsetX_, sy1 + offsetY_, sx2 + offsetX_, sy2 + offsetY_);
            XDrawLine(display_, drawable_, gc_, sx2 + offsetX_, sy2 + offsetY_, sx0 + offsetX_, sy0 + offsetY_);
        }
    }
}

/// Draws a closed, unfilled 4-point loop: (x0,y0)-(x1,y1)-(x2,y2)-
/// (x3,y3)-(x0,y0). Added for flDiamondUpBox()/flDiamondDownBox()'s
/// outer diamond outline; also used by fl.check_browser's checkbox
/// glyph (a rectangular loop, not a diamond).
///
/// Does not decompose into four 2-arg fl_line() calls, which is what
/// FLTK's *unscaled* base loop() does -- same class of shared-vertex
/// rounding mismatch as the 3-point loop()/fl_line() cases above:
/// fl.check_browser's checkbox glyph is exactly the rectangular case,
/// and its outline would pick up corner gaps at scale > 1 the same way
/// flFrame2()'s boxtype bevels do.
/// `Fl_Scalable_Graphics_Driver::loop(x0,y0,x1,y1,x2,y2,x3,y3)`
/// (`src/Fl_Graphics_Driver.cxx`) special-cases both possible point
/// orderings of an axis-aligned rectangle and redirects to rect() (a
/// single atomic Xlib call, already correct -- no shared-vertex
/// boundary to break), falling back to a single uniform-scale, no-
/// decomposition pass only for a genuinely non-rectangular quad (e.g.
/// the diamond boxtype). Ported verbatim, including both orderings.
void loop(int x0, int y0, int x1, int y1, int x2, int y2, int x3, int y3)
{
    if (currentDriver !is null)
    {
        currentDriver.loop(x0, y0, x1, y1, x2, y2, x3, y3);
        return;
    }
    if (x0 == x3 && x1 == x2 && y0 == y1 && y3 == y2)
    {
        int X = x0 > x1 ? x1 : x0;
        int Y = y0 > y3 ? y3 : y0;
        fl_rect(X, Y, abs(x0 - x1) + 1, abs(y0 - y3) + 1);
        return;
    }
    if (x0 == x1 && y1 == y2 && x2 == x3 && y3 == y0)
    {
        int X = x0 > x3 ? x3 : x0;
        int Y = y0 > y1 ? y1 : y0;
        fl_rect(X, Y, abs(x0 - x3) + 1, abs(y0 - y1) + 1);
        return;
    }
    int sx0 = scaledFloor(x0), sy0 = scaledFloor(y0);
    int sx1 = scaledFloor(x1), sy1 = scaledFloor(y1);
    int sx2 = scaledFloor(x2), sy2 = scaledFloor(y2);
    int sx3 = scaledFloor(x3), sy3 = scaledFloor(y3);
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0)
        {
            XDrawLine(display_, drawable_, gc_, sx0 + offsetX_, sy0 + offsetY_, sx1 + offsetX_, sy1 + offsetY_);
            XDrawLine(display_, drawable_, gc_, sx1 + offsetX_, sy1 + offsetY_, sx2 + offsetX_, sy2 + offsetY_);
            XDrawLine(display_, drawable_, gc_, sx2 + offsetX_, sy2 + offsetY_, sx3 + offsetX_, sy3 + offsetY_);
            XDrawLine(display_, drawable_, gc_, sx3 + offsetX_, sy3 + offsetY_, sx0 + offsetX_, sy0 + offsetY_);
        }
    }
}

/// Draws a vertical line from (x,y) to (x,y1). Dispatches to
/// `fl.graphics_driver.currentDriver` first when one is active;
/// otherwise real on Linux, coordinates scaled via `scaledFloor()`.
/// Drawn as a filled rectangle rather
/// than a 1-device-pixel `XDrawLine()` -- see `fl_xyline()`'s own doc
/// comment for why (same fix, same reasoning, just widening in `x`
/// instead of `y`).
void fl_yxline(int x, int y, int y1)
{
    if (currentDriver !is null)
    {
        currentDriver.yxline(x, y, y1);
        return;
    }
    version (linux)
    {
        if (penNeedsXDrawLine_)
        {
            if (gc_ !is null && drawable_ != 0) XDrawLine(display_, drawable_, gc_,
                scaledFloor(x) + offsetX_, scaledFloor(y) + offsetY_,
                scaledFloor(x) + offsetX_, scaledFloor(y1) + offsetY_);
            return;
        }
        int sx, sw;
        if (explicitWideLineWidthPx_ > 0)
        {
            // A genuinely wide, explicitly-requested pen (`lineStyle(
            // lineSolid, N)` with `|N| > 1`) -- fill exactly that many
            // device pixels, centered on `x`, instead of the default-
            // hairline-only formula below (which ignores any
            // explicit width, so without this branch a caller asking
            // for a wide line -- e.g. `lineStyle(lineSolid, 3)` before
            // calling fl_yxline(), as `test/unittest_fast_shapes`' "5"
            // tab's second sub-test does -- would only get a fraction
            // of the requested width, at any scale).
            sw = explicitWideLineWidthPx_;
            sx = scaledFloor(x) - sw / 2;
        }
        else
        {
            sx = scaledFloor(x);
            sw = scaledFloor(x + 1) - sx;
            if (sw < 1) sw = 1;
        }
        int sy0 = scaledFloor(y < y1 ? y : y1);
        // The far endpoint reaches to the *end* of its own logical
        // unit's device-pixel range (floor(n+1)-1), not just the start
        // of it (plain floor(n)) -- see fl_xyline()'s own doc comment
        // for the full reasoning (same fix, same corner-convergence
        // rationale, just the y-axis instead of x).
        int sy1 = scaledFloor((y < y1 ? y1 : y) + 1) - 1;
        int sh = sy1 - sy0 + 1;
        if (gc_ !is null && drawable_ != 0 && sh > 0)
            XFillRectangle(display_, drawable_, gc_, sx + offsetX_, sy0 + offsetY_, cast(uint) sw, cast(uint) sh);
    }
}

/// Draws a vertical line from (x,y) to (x,y1), then a horizontal from
/// (x,y1) to (x2,y1). Ported from Fl_Graphics_Driver::yxline(x,y,y1,x2)
/// (src/Fl_Graphics_Driver.cxx): purely a composition of the two 3-arg
/// primitives above, no driver override needed (FLTK has none
/// either), same "keep the bookkeeping portable" pattern as the
/// 3/4-point fl_line() overloads.
void fl_yxline(int x, int y, int y1, int x2)
{
    fl_yxline(x, y, y1);
    fl_xyline(x, y1, x2);
}

/// Draws a vertical line from (x,y) to (x,y1), then a horizontal from
/// (x,y1) to (x2,y1), then another vertical from (x2,y1) to (x2,y3).
/// Ported from Fl_Graphics_Driver::yxline(x,y,y1,x2,y3); same
/// composition pattern as the 4-arg overload above.
void fl_yxline(int x, int y, int y1, int x2, int y3)
{
    fl_yxline(x, y, y1);
    fl_xyline(x, y1, x2);
    fl_yxline(x2, y1, y3);
}

/// Draws a horizontal line from (x,y) to (x1,y). Dispatches to
/// `fl.graphics_driver.currentDriver` first when one is active;
/// otherwise real on Linux, coordinates scaled via `scaledFloor()`.
///
/// Drawn as a filled rectangle, not a 1-device-pixel `XDrawLine()`, so
/// its *thickness* scales along with everything else: a plain
/// `XDrawLine()` always draws exactly 1 device pixel tall regardless of
/// `scale()`, but "a line at logical row `y`" is supposed to occupy
/// `scaledFloor(y+1) - scaledFloor(y)` device pixels (2 at scale 2,
/// etc.) to stay proportional -- the same corner-rounding convention
/// `fl_rectf()` already uses for its own height. Without this, a
/// multi-line bevel built from adjacent 1-unit-tall `fl_xyline()` calls
/// (`flFrame2()`'s "AAWWMMTT"-style border, used by every plain up/down
/// boxtype) would leave real device-pixel gaps *between* consecutive lines
/// at any scale > 1: a `MenuBar`'s "up" box background,
/// hidden under a solid-fill highlight box (whose own height *does*
/// scale correctly via `fl_rectf()`), would leave a visibly gapped/hatched
/// strip once the highlight was removed and the border tried to
/// restore itself -- invisible at scale 1 (where a 1-device-pixel line
/// already exactly fills its own logical row, so there's no gap to
/// leave), reproducible at both a fractional scale (150%) and a clean
/// integer one (200%). Matches FLTK's own real fix for this
/// (`Fl_Scalable_Graphics_Driver::xyline()`'s pen-width-widening
/// dance) in spirit, not the letter -- a filled rectangle achieves the
/// same "proportional thickness" result without needing this port's
/// deliberately-not-tracked persistent GC line-width state (see this
/// module's own "General line style" section comment for why that
/// state was mostly dropped).
///
/// That "1 logical unit, scale-aware" formula is only
/// the *default*-pen case -- it must not
/// silently ignore any genuinely wide pen an explicit prior
/// `lineStyle(lineSolid, N)` call (`|N| > 1`) set, or a caller
/// asking for a 3-unit-wide line (e.g. `test/unittest_fast_shapes`' "4"
/// tab's second sub-test, which draws a black `fl_xyline()` meant to be
/// 3 units thick, hiding a red rectangle laid out to match) would get a
/// 1-unit-wide one instead, covering only a third of the red rectangle
/// underneath it, at every scale.
/// `explicitWideLineWidthPx_` (see its own doc comment) handles this --
/// still no *general* line-width state, just this one narrow value.
void fl_xyline(int x, int y, int x1)
{
    if (currentDriver !is null)
    {
        currentDriver.xyline(x, y, x1);
        return;
    }
    version (linux)
    {
        if (penNeedsXDrawLine_)
        {
            if (gc_ !is null && drawable_ != 0) XDrawLine(display_, drawable_, gc_,
                scaledFloor(x) + offsetX_, scaledFloor(y) + offsetY_,
                scaledFloor(x1) + offsetX_, scaledFloor(y) + offsetY_);
            return;
        }
        int sy, sh;
        if (explicitWideLineWidthPx_ > 0)
        {
            // See fl_yxline()'s identical branch (its own doc comment
            // has the full writeup, including the real bug this fixes
            // -- `test/unittest_fast_shapes`' "4" tab's second sub-test
            // is this function's own repro).
            sh = explicitWideLineWidthPx_;
            sy = scaledFloor(y) - sh / 2;
        }
        else
        {
            sy = scaledFloor(y);
            sh = scaledFloor(y + 1) - sy;
            if (sh < 1) sh = 1;
        }
        int sx0 = scaledFloor(x < x1 ? x : x1);
        // The far endpoint reaches to the *end* of its own logical
        // unit's device-pixel range (floor(n+1)-1), not just the start
        // of it (plain floor(n)) -- ported from
        // Fl_Scalable_Graphics_Driver::xyline()/yxline()
        // (src/Fl_Graphics_Driver.cxx). Without it, two perpendicular
        // beveled-frame lines meeting at a corner (flFrame2()'s
        // "AAWWMMTT"-style border, used by every plain up/down boxtype)
        // could each independently floor() to non-adjacent device pixels
        // at any scale > 1, leaving a gap at that corner --
        // invisible at scale 1 (where floor(n+1)-1 == floor(n) == n for
        // any integer n, so this is a pure no-op there), reproducible
        // at every scale tested above 1x (up/down box corners showing
        // gaps at 150%/200%/300%, three of the box's four corners
        // affected -- only the one corner where the two independently-
        // floored coordinates happen to land adjacent anyway would
        // survive). Matches FLTK's own real fix exactly, not just
        // in spirit.
        int sx1 = scaledFloor((x < x1 ? x1 : x) + 1) - 1;
        int sw = sx1 - sx0 + 1;
        if (gc_ !is null && drawable_ != 0 && sw > 0)
            XFillRectangle(display_, drawable_, gc_, sx0 + offsetX_, sy + offsetY_, cast(uint) sw, cast(uint) sh);
    }
}

/// Draws a horizontal line from (x,y) to (x1,y), then a vertical from
/// (x1,y) to (x1,y2). Ported from
/// Fl_Graphics_Driver::xyline(x,y,x1,y2); a composition of the two
/// 3-arg primitives above, same pattern as fl_yxline()'s 4-arg
/// overload.
void fl_xyline(int x, int y, int x1, int y2)
{
    fl_xyline(x, y, x1);
    fl_yxline(x1, y, y2);
}

/// Draws a horizontal line from (x,y) to (x1,y), then a vertical from
/// (x1,y) to (x1,y2), then another horizontal from (x1,y2) to (x3,y2).
/// Ported from Fl_Graphics_Driver::xyline(x,y,x1,y2,x3); same
/// composition pattern as the 4-arg overload above.
void fl_xyline(int x, int y, int x1, int y2, int x3)
{
    fl_xyline(x, y, x1);
    fl_yxline(x1, y, y2);
    fl_xyline(x1, y2, x3);
}

/// Fills a 3-sided polygon in the current fl_color(). Dispatches to
/// `fl.graphics_driver.currentDriver` first when one is active;
/// otherwise real on Linux (XFillPolygon, `polygonShapeComplex`/
/// `coordModeOrigin` -- FLTK's own Fl_Xlib_Graphics_Driver::
/// polygon() passes the same two constants); no clipping in the native
/// path (matches fl_rectf()/fl_line()). Coordinates scaled via
/// `scaledFloor()`.
void fl_polygon(int x, int y, int x1, int y1, int x2, int y2)
{
    if (currentDriver !is null)
    {
        currentDriver.polygon(x, y, x1, y1, x2, y2);
        return;
    }
    version (linux)
    {
        XPoint[3] p = [
            XPoint(cast(short)(scaledFloor(x) + offsetX_), cast(short)(scaledFloor(y) + offsetY_)),
            XPoint(cast(short)(scaledFloor(x1) + offsetX_), cast(short)(scaledFloor(y1) + offsetY_)),
            XPoint(cast(short)(scaledFloor(x2) + offsetX_), cast(short)(scaledFloor(y2) + offsetY_))
        ];
        if (gc_ !is null && drawable_ != 0)
            XFillPolygon(display_, drawable_, gc_, p.ptr, cast(int) p.length,
                polygonShapeComplex, coordModeOrigin);
    }
}

/// Fills a 4-sided (convex) polygon in the current fl_color().
/// Dispatches the same way as the 3-point overload above; otherwise
/// real on Linux, same mechanism. Coordinates scaled via `scaledFloor()`.
void fl_polygon(int x, int y, int x1, int y1, int x2, int y2, int x3, int y3)
{
    if (currentDriver !is null)
    {
        currentDriver.polygon(x, y, x1, y1, x2, y2, x3, y3);
        return;
    }
    version (linux)
    {
        XPoint[4] p = [
            XPoint(cast(short)(scaledFloor(x) + offsetX_), cast(short)(scaledFloor(y) + offsetY_)),
            XPoint(cast(short)(scaledFloor(x1) + offsetX_), cast(short)(scaledFloor(y1) + offsetY_)),
            XPoint(cast(short)(scaledFloor(x2) + offsetX_), cast(short)(scaledFloor(y2) + offsetY_)),
            XPoint(cast(short)(scaledFloor(x3) + offsetX_), cast(short)(scaledFloor(y3) + offsetY_))
        ];
        if (gc_ !is null && drawable_ != 0)
            XFillPolygon(display_, drawable_, gc_, p.ptr, cast(int) p.length,
                polygonShapeComplex, coordModeOrigin);
    }
}

/// Sets the color to c, then fills a solid rectangle -- the common
/// "draw a rect in this color" idiom FLTK's own inline wrapper
/// exists for.
void fl_rectf(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    fl_rectf(x, y, w, h);
}

/// Draws a single pixel at (x,y) in the current fl_color(). Ported from
/// `FL/fl_draw.H`'s inline `fl_point()`, which forwards to
/// `Fl_Graphics_Driver::point()` -- at this port's fixed scale of 1,
/// that always reduces to `Fl_Scalable_Graphics_Driver::point()`'s own
/// body, `rectf(x,y,1,1)`, so it's ported directly as that composition
/// rather than a separate `XDrawPoint()` binding.
void point(int x, int y)
{
    fl_rectf(x, y, 1, 1);
}

/// A slightly darker variant of c (67% toward black); see the module
/// note above on why this lives here rather than fl.enumerations.
Color darker(Color c)
{
    return colorAverage(c, black, .67f);
}

/// A slightly lighter variant of c (67% toward white); see the module
/// note above on why this lives here rather than fl.enumerations.
Color lighter(Color c)
{
    return colorAverage(c, white, .67f);
}

// ---------------------------------------------------------------------
// Text drawing (src/fl_draw.cxx + the Xft half of
// src/drivers/Xlib/Fl_Xlib_Graphics_Driver_font_xft.cxx)
// ---------------------------------------------------------------------
//
// Real on Linux via Xft (fl.xft) -- modern FLTK's own default X11 text
// backend (see fl.xft's module comment). Deliberate simplifications
// relative to FLTK:
//
//  - Font matching (unrotated case): FLTK's fontopen() builds an
//    XftPattern by hand (XftPatternAddString/AddInteger/AddDouble +
//    XftFontMatch) so it can fall back to a "core" X font. This just
//    builds a Fontconfig *name string* ("sans:bold:pixelsize=14") and
//    calls the higher-level XftFontOpenName(), which does the same
//    pattern-build-and-match internally -- one function instead of
//    five, with no core-font fallback (Xft is assumed present, see
//    fl.xft). Rotated text (fl_draw(int angle,...)) is the one
//    exception: XftFontOpenName()'s name-string interface has no way to
//    attach a rotation matrix at all, so xftFontForAngled() below does
//    build a real XftPattern/XftFontMatch/XftFontOpenPattern chain,
//    matching FLTK's own fontopen() shape exactly for that one case
//    (still no core-font fallback).
//  - Only the 12 classic built-in fonts fl.enumerations.Font defines
//    (helvetica/courier/times x plain/bold/italic/bold-italic) plus
//    symbol/screen/screen-bold/Zapf Dingbats resolve algorithmically;
//    any other index wraps into that range unless setFont()/setFonts()
//    registered a name for it. The actual
//    Fontconfig family strings resolved to are the generic aliases
//    "sans"/"mono"/"serif" (see getFont()'s
//    own doc comment for the full story -- the literal
//    names "helvetica"/"courier"/"times" don't match
//    FLTK 1.5.0's own built-in font tables and, on a system with a
//    URW "Nimbus" font family installed, resolve to a visibly
//    smaller-metriced font than FLTK's own generic aliases do).
//  - fl_draw(str,x,y,w,h,align): handles '\n'-separated multi-line text
//    and the eight LEFT/RIGHT/CENTER x TOP/BOTTOM/CENTER alignments.
//    The '&'-shortcut-underline convention is real too (fl_draw_shortcut/stripShortcutMarker() below). Real
//    word-wrap is ported too (wrapLine()
//    below, backing both alignWrap here and fl_measure()'s in/out wrap-
//    width parameter) -- breaks only at space boundaries, matching
//    FLTK's expand_text_() (src/fl_draw.cxx): a single word wider
//    than the wrap width is still emitted whole on its own line, never
//    split mid-word. Leading/trailing
//    '@'-symbol glyphs and image-adjacent layout are real too -- see fl.symbols (
//    detectSymbols()/drawSymbol() below) and the Image-taking
//    fl_draw() overload just below detectSymbols() respectively. Still
//    genuinely NOT ported: tab expansion and control-character ^X
//    escaping (expand_text_()'s own interleaved handling for those two
//    -- no caller in this port has needed them yet).
//  - Colors go through a fresh XftColorAllocValue()/XftColorFree() per
//    draw call rather than a cached palette -- matches this module's
//    existing "simple and correct over fast" stance elsewhere (e.g.
//    drawBoxAt()'s per-call color-table lookups).

/// Set by Widget.drawLabel() (fl.widget.d) around a label draw whose
/// widget has Flag.shortcutLabel set, and by fl.menu_item.MenuItem's
/// measure()/draw() around a menu item's own label -- the direct
/// equivalent of FLTK's global `fl_draw_shortcut` (src/fl_draw.cxx),
/// which fl_draw()'s text primitives below consult to decide whether
/// to strip '&'-shortcut markers and underline the following
/// character. A tri-state `int`, matching FLTK's `char` exactly
/// (not just a `bool`): `0` = off (draw '&' literally), `1` = strip
/// and underline (the normal case), `2` = strip but don't underline
/// (FLTK's own "hack value to make '&' disappear", `src/
/// Fl_Choice.cxx` -- used for the *closed* Choice's current-value
/// display, where an underline would be visually misleading since no
/// keyboard accelerator applies there). Platform-independent (pure
/// bookkeeping), unlike the drawing itself.
int fl_draw_shortcut;

/**
 * Strips FLTK's '&'-shortcut marker convention from `line` (`&x` means
 * "underline x"; `&&` is an escaped literal `&`) and reports where the
 * underline should land, as a byte offset into the *returned*
 * (already-stripped) string -- or -1 if no marker was found, or if
 * fl_draw_shortcut is `2` (strip-only mode, see that variable's own
 * doc comment). A no-op (returns `line` unchanged, `underlineAt = -1`)
 * when fl_draw_shortcut is `0`, matching FLTK's own gate (the `&`
 * only means something while a widget with Flag.shortcutLabel -- or a
 * menu item -- is being drawn).
 *
 * Ported from the `&`-handling branch inside `expand_text_()`
 * (`src/fl_draw.cxx`) -- but standalone rather than interleaved with
 * that function's word-wrap/tab/`@`-symbol handling, none of which
 * this port's `fl_draw()` implements either (see this module's own
 * top comment), so there's nothing else to interleave with.
 * Platform-independent (pure string manipulation) -- the actual
 * underline glyph gets drawn by the version(linux) `fl_draw()` body
 * below, which calls this first.
 */
private string stripShortcutMarker(string line, out ptrdiff_t underlineAt)
{
    underlineAt = -1;
    if (fl_draw_shortcut == 0) return line;

    bool hasMarker = false;
    foreach (c; line)
        if (c == '&') { hasMarker = true; break; }
    if (!hasMarker) return line;

    char[] result;
    result.reserve(line.length);
    size_t i = 0;
    while (i < line.length)
    {
        if (line[i] == '&' && i + 1 < line.length)
        {
            if (line[i + 1] == '&')
            {
                result ~= '&';
                i += 2;
                continue;
            }
            if (fl_draw_shortcut != 2) underlineAt = result.length;
            i += 1;
            continue;
        }
        result ~= line[i];
        i++;
    }
    return result.idup;
}

/**
 * Splits `text` into its lines the way FLTK's line-counting loop in
 * `fl_draw()`/`fl_measure()` (`src/fl_draw.cxx`) does: a '\n' ends its
 * line, and a '\n' that is the very last character does *not* start
 * another, empty, line -- `expand_text_()` consumes the '\n' and the loop
 * stops as soon as the returned pointer sits on the terminating NUL. So
 * `"a"` and `"a\n"` are both one line, `"a\n\n"` is two, and `""` is one
 * (empty) line. Counting a phantom trailing line made a one-line label
 * ending in '\n' (every `readln()`/`fgets()` result) be laid out as two,
 * and its vertical centering came out half a line too high.
 *
 * Every returned entry is a slice of `text`.
 */
private const(char)[][] splitTextLines(const(char)[] text)
{
    const(char)[][] result;
    size_t start = 0;
    foreach (i, c; text)
    {
        if (c == '\n')
        {
            result ~= text[start .. i];
            start = i + 1;
        }
    }
    if (start < text.length || result.length == 0)
        result ~= text[start .. $];
    return result;
}

unittest
{
    assert(splitTextLines("") == [""]);
    assert(splitTextLines("a") == ["a"]);
    assert(splitTextLines("a\n") == ["a"]);       // trailing '\n': no phantom line
    assert(splitTextLines("a\nb") == ["a", "b"]);
    assert(splitTextLines("a\nb\n") == ["a", "b"]);
    assert(splitTextLines("a\n\n") == ["a", ""]); // a real empty line stays
    assert(splitTextLines("\n") == [""]);
    assert(splitTextLines("\n\n") == ["", ""]);
    assert(splitTextLines("\nb") == ["", "b"]);
}

/**
 * Word-wraps `line` (assumed to already have no '\n' in it -- callers
 * split on that separately) into however many sub-lines are needed to
 * keep each one's rendered width in the current fl_font() at or under
 * maxWidth pixels. Breaks only between words (runs of non-space
 * characters); a single word wider than maxWidth on its own is still
 * emitted whole rather than split mid-word -- the same rule FLTK's
 * `expand_text_()` (`src/fl_draw.cxx`) uses, just without that
 * function's interleaved tab/`@`-symbol/control-character handling
 * (see this module's top comment for why those stay unported).
 * `maxWidth <= 0` disables wrapping and returns `[line]` unchanged.
 *
 * Every returned entry is a true slice of `line` (never a copy), so a
 * caller can recover a sub-line's offset into the original string via
 * simple pointer arithmetic (`sub.ptr - line.ptr`) -- fl_draw() below
 * relies on exactly that to remap a pre-computed shortcut-underline
 * position from the unwrapped line into whichever wrapped sub-line it
 * landed in.
 */
private const(char)[][] wrapLine(const(char)[] line, int maxWidth)
{
    if (maxWidth <= 0 || line.length == 0) return [line];

    const(char)[][] result;
    size_t lineStart = 0;
    size_t prevWordEnd = 0;
    bool haveWord = false;

    size_t i = 0;
    while (i < line.length)
    {
        while (i < line.length && line[i] == ' ') i++;
        size_t wordStart = i;
        while (i < line.length && line[i] != ' ') i++;
        size_t wordEnd = i;
        if (wordStart == wordEnd) break; // trailing spaces only -- no more words

        int width = cast(int)(width(line[lineStart .. wordEnd]) + 0.5);
        if (haveWord && width > maxWidth)
        {
            result ~= line[lineStart .. prevWordEnd];
            lineStart = wordStart;
        }
        prevWordEnd = wordEnd;
        haveWord = true;
    }
    result ~= line[lineStart .. $];
    return result;
}

/// Result of detectSymbols(): `text` is str with any leading/trailing
/// `@`-symbol reference stripped off (empty leadSymbol/trailSymbol
/// means none was found).
private struct SymbolSplit
{
    const(char)[] text;
    const(char)[] leadSymbol;
    const(char)[] trailSymbol;
}

/**
 * Detects and strips a leading and/or trailing `@`-symbol reference
 * from `str`, matching FLTK's own detection rules (fl_draw()/
 * fl_measure(), `src/fl_draw.cxx`): a leading symbol is `@word`
 * (word = up to the first whitespace or end of string) at the very
 * start, not `@@`; a trailing symbol is the *last* `@` found in
 * whatever remains after the leading symbol is stripped, provided it's
 * at index >= 2 and not itself preceded by `@` (both guards exist so a
 * short string like "@x" can't be double-counted as both). Symbols and
 * `fl.draw`'s own text-drawing feed off `SymbolSplit.text`, which is
 * always the true remaining slice of `str` -- pointer-arithmetic-
 * compatible with the rest of this module's shortcut/wrap machinery,
 * same as wrapLine()'s own results.
 */
private SymbolSplit detectSymbols(const(char)[] str)
{
    SymbolSplit result;
    result.text = str;
    if (str.length == 0) return result;

    const(char)[] rest = str;

    if (rest.length >= 2 && rest[0] == '@' && rest[1] != '@')
    {
        size_t i = 0;
        while (i < rest.length && rest[i] != ' ' && rest[i] != '\t' && rest[i] != '\n') i++;
        result.leadSymbol = rest[0 .. i];
        if (i < rest.length && (rest[i] == ' ' || rest[i] == '\t' || rest[i] == '\n')) i++;
        rest = rest[i .. $];
    }

    ptrdiff_t lastAt = -1;
    foreach_reverse (i, c; rest)
        if (c == '@') { lastAt = i; break; }
    if (lastAt > 1 && rest[lastAt - 1] != '@')
    {
        result.trailSymbol = rest[lastAt .. $];
        rest = rest[0 .. lastAt];
    }

    result.text = rest;
    return result;
}

/**
 * Same leading-symbol detection as detectSymbols(), but a genuinely
 * *different* trailing-symbol rule -- matching FLTK's own
 * `fl_measure()` (not `fl_draw()`'s), which uses the *first* `@` found
 * (via `strchr()`) rather than the last, with a weaker guard (only
 * "not immediately followed by another `@`", no minimum-index check).
 * See fl_measure()'s own call site for why this isn't unified with
 * detectSymbols() despite the near-identical shape.
 */
private SymbolSplit detectSymbolsForMeasure(const(char)[] str)
{
    SymbolSplit result;
    result.text = str;
    if (str.length == 0) return result;

    const(char)[] rest = str;
    const(char)[] sym2 = (rest.length >= 2 && rest[0] == '@' && rest[1] == '@')
        ? rest[2 .. $] : rest;

    if (rest.length >= 2 && rest[0] == '@' && rest[1] != '@')
    {
        size_t i = 0;
        while (i < rest.length && rest[i] != ' ' && rest[i] != '\t' && rest[i] != '\n') i++;
        result.leadSymbol = rest[0 .. i];
        if (i < rest.length && (rest[i] == ' ' || rest[i] == '\t' || rest[i] == '\n')) i++;
        rest = rest[i .. $];
        sym2 = rest;
    }

    foreach (i, c; sym2)
    {
        if (c == '@' && (i + 1 >= sym2.length || sym2[i + 1] != '@'))
        {
            size_t off = (sym2.ptr - rest.ptr) + i;
            result.trailSymbol = rest[off .. $];
            rest = rest[0 .. off];
            break;
        }
    }

    result.text = rest;
    return result;
}

/**
 * Collapses `"@@"` to a literal `"@"` within already-lead/trail-
 * stripped text, and truncates at any remaining lone (unescaped) `@`
 * -- matching `expand_text_()`'s own `c == '@' && draw_symbols` branch
 * (`src/fl_draw.cxx`): a `@` embedded anywhere else in a label isn't a
 * position this layout model knows how to draw (only a leading and/or
 * trailing symbol are ever placed), so FLTK just stops there
 * rather than drawing it literally or erroring.
 */
private const(char)[] unescapeAtSymbols(const(char)[] text)
{
    size_t firstAt = size_t.max;
    foreach (i, c; text) if (c == '@') { firstAt = i; break; }
    if (firstAt == size_t.max) return text;

    char[] result = text[0 .. firstAt].dup;
    size_t i = firstAt;
    while (i < text.length)
    {
        if (text[i] == '@')
        {
            if (i + 1 < text.length && text[i + 1] == '@')
            {
                result ~= '@';
                i += 2;
                continue;
            }
            return result; // lone '@': truncate here, matching FLTK
        }
        result ~= text[i];
        i++;
    }
    return result;
}

/// Raw internal name overrides registered via `setFont()`, keyed by
/// font index (a built-in face 0-15 or a custom `freeFont`+ slot).
/// Ported from `Fl_Fontdesc::name`/FLTK's growable `fl_fonts`
/// table -- this port has no `Fl_Fontdesc` array at all (built-in
/// faces are resolved algorithmically by `getFont()` instead of
/// stored), so only *overridden* slots need storage here; a plain
/// associative array needs no FLTK-style `realloc()`-driven growth
/// for out-of-range `fnum`s either. Platform-independent (a font
/// index's registered name means the same thing regardless of which
/// text backend eventually opens it), so unlike the rest of this
/// section this isn't `version`-gated.
private string[Font] fontNameOverride_;

/// Ported from `static int fl_free_font` (matching FLTK's own
/// name almost exactly) -- the next unused custom-font index
/// `setFonts()` hands out, and the return value of a `setFonts()`
/// call that's already run once (see that function's own guard).
private Font nextFreeFont_ = freeFont;

/// Style-prefix character FLTK's internal font-name format
/// uses: `' '`=plain, `'B'`=bold, `'I'`=italic, `'P'`=bold+italic.
/// Ported from the `switch (*name++)`-style decode both
/// `fontopen()` and `make_raw_name()` do FLTK.
private char fontStyleChar(bool isBold, bool isItalic)
{
    if (isBold && isItalic) return 'P';
    if (isBold) return 'B';
    if (isItalic) return 'I';
    return ' ';
}

/**
 * Gets the raw internal name string for `fnum` -- ported from
 * `Fl::get_font()`/`Fl_Graphics_Driver::font_name(Fl_Font)`. For a
 * `setFont()`-overridden slot, returns exactly what was registered;
 * otherwise synthesizes FLTK's own "style-char + family" built-in
 * format. `fl.core.getFontName()` calls this
 * unconditionally, so this function is not scoped to Linux -- and
 * the built-in family names genuinely differ per platform (FLTK's
 * own separate `built_in_table[]`s: `Fl_Xlib_Graphics_Driver_font_
 * xft.cxx`'s generic Fontconfig aliases "sans"/"mono"/"serif" vs.
 * `Fl_GDI_Graphics_Driver_font.cxx`'s literal Windows family names
 * "Microsoft Sans Serif"/"Courier New"/"Times New Roman"), so *that*
 * part stays a small internal `version` branch rather than being
 * faked into one shared table.
 *
 * The Linux family names are "sans"/"mono"/"serif"
 * (Fontconfig generics), not the literal names "helvetica"/"courier"/"times" --
 * a real metrics difference, not a
 * cosmetic renaming (a URW "Nimbus" install resolves the literal names
 * to a different, differently-metriced font file than the generic
 * aliases do).
 */
string getFont(Font fnum)
{
    if (auto p = fnum in fontNameOverride_) return *p;

    version (Windows)
    {
        if (fnum == symbol) return " Symbol";
        if (fnum == screen) return " Terminal";
        if (fnum == screenBold) return "BTerminal";
        if (fnum == zapfDingbats) return " Wingdings";
        static immutable string[3] families = ["Microsoft Sans Serif", "Courier New", "Times New Roman"];
        int idx = ((fnum % 12) + 12) % 12; // defensively handle negative/out-of-range faces
        return fontStyleChar((idx & 1) != 0, (idx & 2) != 0) ~ families[idx / 4];
    }
    else
    {
        if (fnum == symbol) return " symbol";
        if (fnum == screen) return " screen";
        if (fnum == screenBold) return "Bscreen";
        if (fnum == zapfDingbats) return " zapf dingbats";
        static immutable string[3] families = ["sans", "mono", "serif"];
        int idx = ((fnum % 12) + 12) % 12; // defensively handle negative/out-of-range faces
        return fontStyleChar((idx & 1) != 0, (idx & 2) != 0) ~ families[idx / 4];
    }
}

/**
 * Registers `name` as font `fnum`'s internal name, overriding whatever
 * `getFont()` would otherwise resolve it to (built-in or not) --
 * ported from `Fl::set_font(Fl_Font, const char*)`. Any already-open
 * font cached for `fnum` (under its *old* name, at any size) is
 * dropped so the next `fl_font()` call re-resolves through the new
 * name, matching FLTK's own cache-invalidating `d.font(-1, 0)`
 * call at the end of `Fl::set_font()` -- each platform's own font
 * cache lives behind its own leaf implementation (`fl.xft`'s
 * `fontCache_`/`currentFontFace_` on Linux, `fl.gdi_graphics_driver.
 * GdiGraphicsDriver`'s own cache on Windows), so this needs a small
 * per-platform branch to reach the right one.
 */
void setFont(Font fnum, string name)
{
    fontNameOverride_[fnum] = name;
    version (linux)
    {
        foreach (key; fontCache_.keys.dup)
            if (key.face == fnum) fontCache_.remove(key);
        if (currentFontFace_ == fnum) currentFontFace_ = -1;
    }
    else version (Windows)
    {
        if (auto gdi = cast(GdiGraphicsDriver) currentDriver)
            gdi.invalidateFontCache(fnum);
    }
}

/// Copies `from`'s name onto `fnum` -- ported from
/// `Fl::set_font(Fl_Font, Fl_Font)`.
void setFont(Font fnum, Font from)
{
    setFont(fnum, getFont(from));
}

version (linux)
{
    private struct FontKey { Font face; Fontsize size; }
    private XftFont*[FontKey] fontCache_;

    /// The angled sibling of `FontKey`/`fontCache_`, keyed on
    /// `(face, size, angle)` -- matches FLTK's real
    /// `Fl_Xlib_Font_Descriptor` cache, which keys on the same triple
    /// (see `xftFontForAngled()`). Kept as a genuinely separate table
    /// rather than folding `angle` into `FontKey` itself: the
    /// overwhelming majority of lookups are angle-0, and those already
    /// go through the cheaper `XftFontOpenName()` path via `fontCache_`
    /// -- there's no reason to make every unrotated lookup pay for a
    /// wider key.
    private struct AngledFontKey { Font face; Fontsize size; int angle; }
    private XftFont*[AngledFontKey] angledFontCache_;

    private Font currentFontFace_ = -1;
    private Fontsize currentFontSize_ = 0;
    private XftFont* currentXftFont_;
    /// The `currentScale()` value in effect when `currentXftFont_` was
    /// last resolved -- `fl_font()`'s own
    /// `face == currentFontFace_ && size == currentFontSize_`
    /// short-circuit predates any scale concept and only compares FLTK-
    /// unit face/size, so without this a scale change with the same
    /// (face, size) already current would wrongly keep reusing a font
    /// opened at the *old* device pixel size. `xftFontFor()`'s own
    /// `fontCache_` is keyed on the actual (already-scaled) size passed
    /// to it, so it doesn't have this problem -- only this short-circuit
    /// does, since it runs before that lookup.
    private float currentFontScale_ = 1.0f;

    /// Builds the Fontconfig name string for one of the 16 classic
    /// built-in fonts (see fl.enumerations.Font). Faces 0..11 (the
    /// helvetica/courier/times x plain/bold/italic/bold-italic grid):
    /// family from face/4, bold from bit 0 of face%4, italic from bit 1
    /// -- e.g. helveticaBoldItalic (3) is "helvetica:bold:italic:pixelsize=N".
    ///
    /// Faces 12..15 (symbol/screen/screenBold/zapfDingbats)
    /// must NOT fall through the same `face % 12` wraparound as an
    /// out-of-range face -- that would silently alias them back onto the
    /// helvetica/courier/times grid (e.g. face 12 to plain
    /// helvetica) instead of requesting their own distinct families.
    /// Ported faithfully from FLTK's real 16-entry
    /// `built_in_table` (`Fl_Xlib_Graphics_Driver_font_xft.cxx`): face
    /// 12 requests family "symbol", 13/14 request "screen" (13 plain,
    /// 14 bold -- FLTK has no italic/bold-italic screen variant
    /// either), 15 requests "zapf dingbats". Whether the *system* has a
    /// real Symbol/Zapf Dingbats font installed is an environment
    /// concern Fontconfig's own fallback matching handles identically
    /// to FLTK (same library, same query) -- not something this
    /// port controls or needs to special-case further. Only genuinely
    /// out-of-range faces (negative, or >= freeFont) still wrap via
    /// modulo onto the 0..11 grid, matching this function's previous
    /// defensive-fallback intent for those.
    private string fontconfigName(Font face, Fontsize size)
    {
        import std.conv : to;

        string family;
        bool bold, italic;
        fontFamilyStyle(face, family, bold, italic);

        string style;
        if (bold && italic) style = ":bold:italic";
        else if (bold) style = ":bold";
        else if (italic) style = ":italic";

        return family ~ style ~ ":pixelsize=" ~ size.to!string;
    }

    /// Decodes `face` into its Fontconfig family name plus bold/italic
    /// flags -- the same decoding `fontconfigName()` above builds its
    /// combined `"family:bold:italic:pixelsize=N"` name string from,
    /// factored out here so `xftFontForAngled()`'s `FcPattern`-based
    /// path (which needs the components separately, not a name string)
    /// can't silently diverge from it.
    private void fontFamilyStyle(Font face, out string family, out bool bold, out bool italic)
    {
        // A setFont()-registered name (built-in slot or custom) always
        // wins over the algorithmic built-in resolution below --
        // matches FLTK's fontopen() decoding the *name's* own
        // leading style character rather than ever consulting `face`
        // itself once a name string is in hand.
        if (auto p = face in fontNameOverride_)
        {
            string raw = *p;
            char c0 = raw.length > 0 ? raw[0] : ' ';
            bool recognized = c0 == ' ' || c0 == 'B' || c0 == 'I' || c0 == 'P';
            family = (recognized && raw.length > 0) ? raw[1 .. $] : raw;
            bold = c0 == 'B' || c0 == 'P';
            italic = c0 == 'I' || c0 == 'P';
            return;
        }

        if (face == symbol) { family = "symbol"; return; }
        if (face == screen) { family = "screen"; return; }
        if (face == screenBold) { family = "screen"; bold = true; return; }
        if (face == zapfDingbats) { family = "zapf dingbats"; return; }

        static immutable string[3] families = ["sans", "mono", "serif"];
        int idx = ((face % 12) + 12) % 12; // defensively handle negative/out-of-range faces
        family = families[idx / 4];
        bold = (idx & 1) != 0;
        italic = (idx & 2) != 0;
    }

    /**
     * Adds every font Fontconfig knows about to the custom-font range
     * (`freeFont` and up), returning the new, larger `freeFont`-
     * equivalent boundary (one past the last font index now valid).
     * Ported from `Fl_Xlib_Graphics_Driver::set_fonts()` -- a real
     * Fontconfig enumeration (`fl.fontconfig`'s bindings), not a stub.
     *
     * `pattern` is accepted for API fidelity but, matching FLTK's
     * own doc comment on this exact function ("for now I'm ignoring
     * the pattern_name and just getting everything... Blimey! What a
     * hack!"), not actually consulted -- every font Fontconfig lists is
     * always added, regardless of `pattern`.
     *
     * Simplified relative to FLTK's `make_raw_name()`: only the
     * `Bold`/`Italic`/`Oblique`/`SuperBold` style keywords are decoded
     * into the `B`/`I`/`P` prefix this port's font names use (covering
     * the overwhelming majority of real-world fonts); FLTK's
     * additional decorative suffix handling for `Demi Bold`/`Black`/
     * `Light`/`Medium` (appending those words to the visible name, with
     * no effect on the bold/italic encoding itself) is not ported --
     * FLTK's own doc comment already calls the full parser "just a
     * mess". Also unlike FLTK, this doesn't call `fl_open_display()`
     * first: Fontconfig enumeration needs no X connection at all (only
     * `getFontSizes()`'s hypothetical per-family size query would, and
     * this port's version of that is pure Fontconfig too -- see its own
     * doc comment).
     */
    Font setFonts(string pattern = "*")
    {
        import fl.fontconfig;
        import std.string : toStringz, fromStringz;
        import std.algorithm.sorting : sort;
        import core.stdc.stdlib : free;

        if (nextFreeFont_ > freeFont) return nextFreeFont_; // already been here, matches FLTK's guard

        if (!FcInit()) return freeFont;

        auto fntPattern = FcPatternCreate();
        auto objSet = FcObjectSetCreate();
        FcObjectSetAdd(objSet, FC_FAMILY.ptr);
        FcObjectSetAdd(objSet, FC_STYLE.ptr);
        auto fntSet = FcFontList(null, fntPattern, objSet);
        FcPatternDestroy(fntPattern);
        FcObjectSetDestroy(objSet);

        if (fntSet !is null)
        {
            string[] names;
            names.reserve(fntSet.nfont);
            foreach (i; 0 .. fntSet.nfont)
            {
                FcChar8* raw = FcNameUnparse(fntSet.fonts[i]);
                if (raw is null) continue;
                string full = cast(string)(cast(char*) raw).fromStringz.idup;
                free(raw);

                // "Family:style=Bold Italic,ko variant,..." -- keep
                // only the family (up to the first ':') and, of that,
                // only the first comma-separated name (matches
                // FLTK's own "keep the first remaining name entry"
                // choice for multi-name/CJK-variant fonts).
                string family = full;
                size_t colon = family.length;
                foreach (j, c; family) if (c == ':') { colon = j; break; }
                family = family[0 .. colon];
                size_t comma = family.length;
                foreach (j, c; family) if (c == ',') { comma = j; break; }
                family = family[0 .. comma];

                string style = (colon < full.length) ? full[colon + 1 .. $] : null;
                bool isBold = false, isItalic = false;
                import std.string : indexOf;
                import std.uni : toLower;
                string styleLower = style.toLower;
                if (styleLower.indexOf("bold") >= 0 || styleLower.indexOf("superbold") >= 0)
                    isBold = true;
                if (styleLower.indexOf("italic") >= 0 || styleLower.indexOf("oblique") >= 0)
                    isItalic = true;

                names ~= fontStyleChar(isBold, isItalic) ~ family;
            }
            FcFontSetDestroy(fntSet);

            // Must be a case-insensitive compare, matching FLTK's
            // `fl_ascii_strcasecmp()`-based qsort: a plain case-
            // sensitive `<` compare on D strings sorts
            // by codepoint, putting every uppercase-initial family
            // before every lowercase one, e.g. "Z003" before "aakar".
            import std.uni : sicmp;
            names.sort!((a, b) => sicmp(a[1 .. $], b[1 .. $]) < 0);

            foreach (name; names)
            {
                setFont(nextFreeFont_, name);
                nextFreeFont_++;
            }
        }

        return nextFreeFont_;
    }

    /**
     * Returns every pixel size Fontconfig lists as fixed for `fnum`'s
     * family, via `sizes` -- `[0]` alone means "scalable" (works at any
     * size), matching FLTK's own convention for outline/TrueType
     * fonts (which is what `sizes == [0]` will be for the overwhelming
     * majority of fonts on a modern system). Returns `sizes.length`.
     * Ported from `Fl_Xlib_Graphics_Driver::get_font_sizes()` -- that
     * function queries via `XftListFonts()` (a C-variadic function this
     * port deliberately doesn't bind, see `fl.fontconfig`'s own module
     * comment), so this queries the same underlying Fontconfig data
     * directly instead (`FcPatternGetDouble()` on `FC_PIXEL_SIZE`),
     * which is what `XftListFonts()` itself ultimately does.
     */
    int getFontSizes(Font fnum, out int[] sizes)
    {
        import fl.fontconfig;
        import std.string : toStringz;
        import std.algorithm.sorting : sort;

        string raw = getFont(fnum);
        char c0 = raw.length > 0 ? raw[0] : ' ';
        bool recognized = c0 == ' ' || c0 == 'B' || c0 == 'I' || c0 == 'P';
        string family = (recognized && raw.length > 0) ? raw[1 .. $] : raw;

        auto pat = FcPatternCreate();
        FcPatternAddString(pat, FC_FAMILY.ptr, cast(const(FcChar8)*) family.toStringz());
        auto objSet = FcObjectSetCreate();
        FcObjectSetAdd(objSet, FC_PIXEL_SIZE.ptr);
        auto fs = FcFontList(null, pat, objSet);
        FcPatternDestroy(pat);
        FcObjectSetDestroy(objSet);

        int[] result = [0]; // claim all fonts are scalable, matching FLTK's array[0] = 0
        if (fs !is null)
        {
            foreach (i; 0 .. fs.nfont)
            {
                double v;
                if (FcPatternGetDouble(fs.fonts[i], FC_PIXEL_SIZE.ptr, 0, &v) == FcResult.fcResultMatch)
                    result ~= cast(int) v;
            }
            FcFontSetDestroy(fs);
        }
        result[1 .. $].sort();
        sizes = result;
        return cast(int) result.length;
    }

    /// Looks up (opening and caching, if new) the XftFont for (face,
    /// size). Returns null if Xft couldn't open any matching font.
    ///
    /// **Only caches a result once a real display is open.** A widget
    /// can legitimately call fl_font() (directly, or via height()/
    /// width() during layout) before any window has been shown --
    /// fl.file_browser's itemHeight()/itemWidth() do exactly this from
    /// insertNode(), to keep a running fullHeight_/maxWidth_ as items
    /// are added, which can happen well before the first show(). If a
    /// lookup with `display_ is null` were cached, it would permanently
    /// poison this (face, size) for the rest of the process -- every
    /// later real draw would keep seeing a stale null font, even after
    /// a display exists, since the cache is never invalidated. Caching
    /// is safe (and desirable, to avoid repeated failed
    /// XftFontOpenName() calls) only for a lookup that had a real
    /// display to try against.
    private XftFont* xftFontFor(Font face, Fontsize size)
    {
        auto key = FontKey(face, size);
        if (auto p = key in fontCache_) return *p;

        if (display_ is null) return null;

        import std.string : toStringz;
        XftFont* f = XftFontOpenName(display_, screen_, fontconfigName(face, size).toStringz());
        fontCache_[key] = f;
        return f;
    }

    /**
     * The angled sibling of `xftFontFor()` -- opens (and caches, keyed
     * on `(face, size, angle)`) a rotated variant of `face`/`size` via a
     * hand-built `FcPattern` carrying an `FC_MATRIX` rotation, since
     * `XftFontOpenName()`'s simple name-string interface has no way to
     * express a rotation matrix at all. Ported from `fontopen()`'s
     * non-XLFD branch (`Fl_Xlib_Graphics_Driver_font_xft.cxx`) -- the
     * same family/weight/slant/pixel-size pattern fields
     * `XftFontOpenName()` resolves internally from a name string, built
     * by hand here instead so `FC_MATRIX` can be attached alongside
     * them. Returns null if Xft couldn't open any matching font, or (see
     * `xftFontFor()`'s own doc comment for why) if there's no real
     * display yet -- not cached in that case, for the identical reason.
     */
    private XftFont* xftFontForAngled(Font face, Fontsize size, int angle)
    {
        auto key = AngledFontKey(face, size, angle);
        if (auto p = key in angledFontCache_) return *p;

        if (display_ is null) return null;

        import fl.fontconfig;
        import std.math : cos, sin, PI;
        import std.string : toStringz;

        string family;
        bool bold, italic;
        fontFamilyStyle(face, family, bold, italic);

        FcPattern* pat = FcPatternCreate();
        FcPatternAddString(pat, FC_FAMILY.ptr, cast(const(FcChar8)*) family.toStringz());
        FcPatternAddInteger(pat, FC_WEIGHT.ptr, bold ? FC_WEIGHT_BOLD : FC_WEIGHT_MEDIUM);
        FcPatternAddInteger(pat, FC_SLANT.ptr, italic ? FC_SLANT_ITALIC : FC_SLANT_ROMAN);
        FcPatternAddDouble(pat, FC_PIXEL_SIZE.ptr, cast(double) size);

        // Starting from the identity matrix and rotating by `angle`
        // degrees always produces exactly {cos,-sin,sin,cos} -- see
        // fl.fontconfig.FcMatrix's own doc comment.
        double rad = PI * cast(double) angle / 180.0;
        FcMatrix m = FcMatrix(cos(rad), -sin(rad), sin(rad), cos(rad));
        FcPatternAddMatrix(pat, FC_MATRIX.ptr, &m);

        FcResult matchResult;
        FcPattern* matchPat = XftFontMatch(display_, screen_, pat, &matchResult);
        XftFont* f = matchPat !is null ? XftFontOpenPattern(display_, matchPat) : null;
        // matchPat is owned by Fontconfig's own cache, not destroyed here
        // -- matches FLTK's own comment on this exact call.
        FcPatternDestroy(pat);

        angledFontCache_[key] = f;
        return f;
    }

    /// Decodes c (see colorToRgb8()) into an Xft color, allocated
    /// fresh -- caller must XftColorFree() it.
    private XftColor xftColorFor(Color c)
    {
        ubyte r, g, b;
        colorToRgb8(c, r, g, b);
        XRenderColor rc;
        // 257 = 65535 / 255: exact 8-bit -> 16-bit channel scaling.
        rc.red = cast(ushort)(r * 257);
        rc.green = cast(ushort)(g * 257);
        rc.blue = cast(ushort)(b * 257);
        rc.alpha = 0xFFFF;
        XftColor result;
        XftColorAllocValue(display_, visual_, colormap_, &rc, &result);
        return result;
    }

    /// Sets the font used by subsequent fl_draw()/width()/
    /// height()/descent() calls (the no-arg/current-font forms).
    /// `size` is a FLTK-unit size (what `fl_size()` reports back) --
    /// the font is actually opened at `size * currentScale()` device
    /// pixels, ported from
    /// `Fl_Scalable_Graphics_Driver::font()`'s own `font_unscaled(face,
    /// Fl_Fontsize(size * scale())); fontsize_ = size;` split.
    ///
    /// The `face == currentFontFace_ && size == currentFontSize_`
    /// short-circuit only applies when `currentXftFont_` is already a
    /// real font *and* the scale hasn't changed since -- otherwise a
    /// caller that asked for this exact (face, size) before any display
    /// existed (see xftFontFor()'s own doc comment) would stay stuck
    /// with a null font forever, even after later fl_font() calls with
    /// a real display available; and a scale change alone (same face,
    /// same FLTK-unit size) would wrongly keep reusing a font opened at
    /// the old device pixel size (see `currentFontScale_`'s own
    /// comment).
    void fl_font(Font face, Fontsize size)
    {
        float s = currentScale();
        if (face == currentFontFace_ && size == currentFontSize_
            && s == currentFontScale_ && currentXftFont_ !is null)
            return;
        currentFontFace_ = face;
        currentFontSize_ = size;
        currentFontScale_ = s;
        int devSize = cast(int)(size * s);
        if (devSize < 1) devSize = 1;
        currentXftFont_ = xftFontFor(face, cast(Fontsize) devSize);
    }


    /// Draws all of str at (x,y), baseline-positioned -- the plain,
    /// no-alignment/no-wrap form. Ported from FLTK's own
    /// `fl_draw(const char*, int, int)` (`src/fl_font.cxx`), which is
    /// just as thin there: `fl_draw(str, strlen(str), x, y);`.
    void fl_draw(const(char)[] str, int x, int y)
    {
        fl_draw(str, cast(int) str.length, x, y);
    }

    /**
     * Draws str at (x,y), rotated by angle degrees counterclockwise --
     * ported from `fl_draw(int,const char*,int,int)` (`src/fl_font.cxx`),
     * which forwards to `Fl_Graphics_Driver::draw(int angle,...)`.
     *
     * `currentDriver` dispatch is checked first, same as every other
     * text primitive here, so an SVG/PostScript-file backend gets the
     * angle too. The plain on-screen/offscreen Xft path (`currentDriver
     * is null`) is real as well: ported from
     * `Fl_Xlib_Graphics_Driver::draw_unscaled(int angle,...)`
     * (`Fl_Xlib_Graphics_Driver_font_xft.cxx`) -- temporarily swaps
     * `currentXftFont_` to a rotated variant of the current face/size
     * (`xftFontForAngled()`, an `FC_MATRIX`-carrying `FcPattern`, cached
     * per `(face, size, angle)` rather than just `(face, size)`), draws
     * through the ordinary 3-arg leaf below, then restores the unrotated
     * font -- matching FLTK's own
     * `fl_xft_font(angle); draw_unscaled(...); fl_xft_font(0);` shape
     * exactly. A no-op angle (0, or a lookup failure) falls through to
     * the plain unrotated draw unchanged.
     */
    void fl_draw(int angle, const(char)[] str, int nChars, int x, int y)
    {
        if (currentDriver !is null)
        {
            currentDriver.draw(angle, str, nChars, x, y);
            return;
        }
        if (angle == 0)
        {
            fl_draw(str, nChars, x, y);
            return;
        }
        int devSize = cast(int)(currentFontSize_ * currentFontScale_);
        if (devSize < 1) devSize = 1;
        XftFont* angled = xftFontForAngled(currentFontFace_, cast(Fontsize) devSize, angle);
        if (angled is null)
        {
            fl_draw(str, nChars, x, y);
            return;
        }
        XftFont* saved = currentXftFont_;
        currentXftFont_ = angled;
        fl_draw(str, nChars, x, y);
        currentXftFont_ = saved;
    }

    /// ditto, the plain no-length form.
    void fl_draw(int angle, const(char)[] str, int x, int y)
    {
        fl_draw(angle, str, cast(int) str.length, x, y);
    }

    /// Draws str aligned within (x,y,w,h) -- see the section comment
    /// above for exactly what's simplified relative to FLTK. A
    /// thin convenience forward to the image-aware overload below with
    /// no image, matching FLTK's own default-argument relationship
    /// (`Fl_Image *img = 0` on the one real `fl_draw(...)` FLTK has)
    /// rather than two independently-maintained implementations.
    void fl_draw(string str, int x, int y, int w, int h, Align alignment)
    {
        fl_draw(str, x, y, w, h, alignment, null, 0);
    }

    /// The per-line text-drawing hook `fl_draw(str,x,y,w,h,align,
    /// callthis,img,spacing)` below calls instead of drawing directly --
    /// ported from FLTK's `void (*callthis)(const char*,int,int,int)`
    /// function-pointer parameter (`FL/fl_draw.H`). A D delegate rather
    /// than a function-pointer+`void*` pair, per CONVENTIONS.md's established
    /// callback convention -- the closures this backs (`fl_shadow_label`/
    /// `fl_engraved_label`/`fl_embossed_label`, `fl.widget`'s `Label`)
    /// already capture whatever state they need directly.
    alias DrawTextCb = void delegate(const(char)[] str, int n, int x, int y);

    /**
     * Draws str aligned within (x,y,w,h), plus img composed alongside
     * it per alignment (FL_ALIGN_IMAGE_NEXT_TO_TEXT: image to the
     * left/right of the text, selected by FL_ALIGN_TEXT_OVER_IMAGE;
     * otherwise: image above/below the text, same flag selecting
     * which). Ported from fl_draw(str,x,y,w,h,align,void(*)(...),img,
     * draw_symbols,spacing) (src/fl_draw.cxx) -- FLTK's *real*
     * implementation of this whole layout algorithm; the callback-free
     * overload just below is, matching FLTK exactly (`fl_draw(str,
     * x,y,w,h,align,fl_draw,img,draw_symbols,spacing)`, `src/fl_draw.cxx`),
     * a one-line forward to this one with `callthis` defaulted to a
     * closure over the plain `fl_draw(str,n,x,y)` primitive above.
     * `callthis` stands in for FLTK's `void(*)(const char*,int,int,
     * int)`; every other line-drawing overload FLTK has (used by
     * `fl_shadow_label()`/`fl_engraved_label()`/`fl_embossed_label()`,
     * `src/fl_engraved_label.cxx`, backing `Labeltype.shadowLabel`/
     * `engravedLabel`/`embossedLabel` in `fl.widget`) passes a
     * multi-pass "draw the same text several times at small pixel
     * offsets in different shades" callback here instead. FLTK's
     * `draw_symbols` ('@'-leading-symbol) feature is real:
     * the body below detects/draws leading and trailing '@' symbols
     * (`detectSymbols()`/`drawSymbol()`) unless `drawSymbols` is
     * false, FLTK's `draw_symbols = 0` -- `fl.browser` passes that for
     * item text, as `Fl_Browser::item_draw()` does. It comes after
     * `spacing` here (FLTK has it before), so existing positional
     * `spacing` arguments keep working. FL_ALIGN_IMAGE_BACKDROP is
     * deliberately ignored here (img is treated as absent) -- that
     * alignment mode is Widget's own drawBackdrop()'s job (ported
     * from Fl_Widget::draw_backdrop()), called separately, matching
     * FLTK's own division of labor exactly (fl_draw() itself does
     * the same img=0 substitution for FL_ALIGN_IMAGE_BACKDROP).
     */
    void fl_draw(string str, int x, int y, int w, int h, Align alignment, Image img, int spacing = 0,
        bool drawSymbols = true)
    {
        fl_draw(str, x, y, w, h, alignment,
            (const(char)[] s, int n, int X, int Y) { fl_draw(s, n, X, Y); }, img, spacing, drawSymbols);
    }

    /// ditto, the real implementation -- see the doc comment above.
    void fl_draw(string str, int x, int y, int w, int h, Align alignment, DrawTextCb callthis, Image img, int spacing = 0,
        bool drawSymbols = true)
    {
        if (str.length == 0 && img is null) return;
        if (img !is null && (alignment & alignImageBackdrop)) img = null;
        if (alignment & alignClip) pushClip(x, y, w, h);
        scope(exit) if (alignment & alignClip) popClip();

        int lineHeight = height();
        int desc = descent();

        bool imgvert = (alignment & alignImageNextToText) == 0; // true: image above/below text
        int imgtotal = (img !is null && !imgvert) ? img.w() + spacing : 0;

        // Leading/trailing '@'-symbol detection (fl.symbols) -- see
        // detectSymbols()'s own doc comment. symwidth0/symwidth1 start
        // as FLTK's own initial guess (min(w,h)) and get corrected
        // to `nLines * lineHeight` once the real line count is known
        // (below), same two-step FLTK itself uses.
        // drawSymbols false (FLTK's draw_symbols = 0, e.g. Fl_Browser's
        // item text): no symbols, and '@@' stays as written.
        auto detected = drawSymbols ? detectSymbols(str) : SymbolSplit(str);
        const(char)[] textOnly = drawSymbols ? unescapeAtSymbols(detected.text) : detected.text;
        int symwidth0 = detected.leadSymbol.length ? (w < h ? w : h) : 0;
        int symwidth1 = detected.trailSymbol.length ? (w < h ? w : h) : 0;
        int symtotal = symwidth0 + symwidth1;

        // Split on '\n', strip '&'-shortcut markers per raw line (so
        // the underline glyph -- not the literal '&' -- is what
        // determines width/position), then, when alignWrap is set,
        // word-wrap each stripped line to fit the text area (w, minus
        // any horizontal image space and symbol space) via wrapLine().
        // Every wrapLine() result is a true slice of its stripped line,
        // so the underline offset (computed against the *unwrapped*
        // stripped line) is remapped into whichever sub-line it landed
        // in by simple pointer arithmetic -- see wrapLine()'s own doc
        // comment.
        const(char)[][] lines;
        ptrdiff_t[] underlineAt;

        void addLine(const(char)[] rawLine, int wrapBudget)
        {
            ptrdiff_t ul;
            string stripped = stripShortcutMarker(rawLine.idup, ul);
            if (alignment & alignWrap)
            {
                foreach (sub; wrapLine(stripped, wrapBudget))
                {
                    size_t offset = sub.ptr - stripped.ptr;
                    lines ~= sub;
                    underlineAt ~= (ul >= 0 && ul >= offset && ul < offset + sub.length)
                        ? ul - offset : -1;
                }
            }
            else
            {
                lines ~= stripped;
                underlineAt ~= ul;
            }
        }

        void buildLines(int wrapBudget)
        {
            lines = null;
            underlineAt = null;
            // No early return for empty textOnly: FLTK's own line-
            // counting loop (`for (p = str, lines = 0; p;) { ...;
            // lines++; if (!*e || ...) break; ...}`, src/fl_draw.cxx)
            // always executes its body at least once whenever `str`
            // itself is non-null -- which, given this function's own
            // `str.length == 0 && img is null` guard above, is always
            // true by the time buildLines() runs. `textOnly` can only
            // be empty here because a leading/trailing '@'-symbol
            // consumed the entire string (see detectSymbols()), and
            // FLTK still counts that as one (empty) "line" -- this
            // is what makes the symwidth-correction step below fire
            // even for a pure-symbol label with no other text, so
            // symwidth0/1 shrink from the initial `min(w,h)` guess down
            // to one real line-height, matching FLTK's rendered
            // symbol size. Without this, a
            // pure-symbol label's `nLines` would stay at 0, so the correction would never
            // run and the symbol would draw at the *full* box size
            // instead of FLTK's single-line-height default.
            // (splitTextLines() also drops the phantom empty line after a
            // trailing '\n' -- see its own doc comment.)
            foreach (rawLine; splitTextLines(textOnly))
                addLine(rawLine, wrapBudget);
        }

        buildLines(w - imgtotal - symtotal);
        // Ported from FLTK's own `if (str) {...} else lines = 0;`
        // (src/fl_draw.cxx) -- FLTK's line-counting loop only runs
        // at all when `str` is a non-null pointer; a genuinely absent
        // label (`str == NULL`) always gives `lines = 0`, *independent*
        // of whether an image is present. `buildLines()` above can't
        // replicate that itself (it unconditionally calls `addLine()`
        // at least once, deliberately, so a pure-`@`-symbol label with
        // no other text -- `str` non-null but `textOnly` empty after
        // symbol extraction -- still gets counted as 1 line, matching
        // FLTK and needed for the symwidth-correction step below).
        // The distinction is `str is null` (D's own equivalent of `str
        // == NULL`) vs. `str !is null && str.length == 0` (FLTK's
        // non-null empty string, still 1 line) -- checking `str.length
        // == 0` alone (this function's own early-return guard above)
        // conflates the two. A widget with an image but no label text
        // (e.g. a plain `Box` used purely as an image canvas) has
        // `label_.text is null`, not `""`, so without this distinction
        // `nLines` would come out 1 instead of 0, shifting the image's
        // vertical centering by `-lineHeight/2` and leaving the
        // remainder of the label box unpainted (e.g.
        // `examples/animgifimage-resize`'s GIF getting its top edge
        // cropped and a checkered-background strip
        // exposed at the bottom).
        int nLines = str is null ? 0 : cast(int) lines.length;

        // Correct symwidth0/symwidth1 to the real per-symbol size now
        // that the line count is known; if that changes the wrap
        // budget, rebuild once more for full consistency (FLTK
        // itself only does this for its own multi-line path -- see
        // detectSymbols()'s and this block's own doc comments for the
        // deliberate simplification of always doing it uniformly here).
        if (nLines > 0)
        {
            if (symwidth0) symwidth0 = nLines * lineHeight;
            if (symwidth1) symwidth1 = nLines * lineHeight;
        }
        int newSymtotal = symwidth0 + symwidth1;
        if (newSymtotal != symtotal)
        {
            symtotal = newSymtotal;
            buildLines(w - imgtotal - symtotal);
            nLines = cast(int) lines.length;
        }

        int strw = 0;
        foreach (line; lines)
        {
            int lw = cast(int)(width(line) + 0.5);
            if (lw > strw) strw = lw;
        }
        int symoffset = strw; // FLTK's own "widest text line" stand-in

        int strh = nLines * lineHeight;
        int imgh = (img !is null && imgvert) ? img.h() + spacing : 0;

        int ypos;
        if (alignment & alignBottom)
            ypos = y + h - (nLines - 1) * lineHeight - imgh;
        else if (alignment & alignTop)
            ypos = y + lineHeight;
        else
            ypos = y + (h - nLines * lineHeight - imgh) / 2 + lineHeight;

        // Draw the image if located *above* the text.
        if (img !is null && imgvert && !(alignment & alignTextOverImage))
        {
            if (img.w() > symoffset) symoffset = img.w();
            int xpos;
            if (alignment & alignLeft) xpos = x + symwidth0;
            else if (alignment & alignRight) xpos = x + w - img.w() - symwidth1;
            else xpos = x + (w - img.w() - symtotal) / 2 + symwidth0;
            img.draw(xpos, ypos - lineHeight);
            ypos += img.h() + spacing;
        }

        // Draw the image if either on the *left* or *right* of the text.
        int imgw0 = 0, imgw1 = 0;
        if (img !is null && !imgvert)
        {
            int xpos;
            if (alignment & alignTextOverImage)
            {
                // Image to the right of the text.
                imgw1 = img.w() + spacing;
                if (alignment & alignLeft) xpos = x + symwidth0 + strw + 1;
                else if (alignment & alignRight) xpos = x + w - symwidth1 - imgw1 + 1;
                else xpos = x + (w - strw - symtotal - imgw1) / 2 + symwidth0 + strw + 1;
                xpos += spacing;
            }
            else
            {
                // Image to the left of the text.
                imgw0 = img.w() + spacing;
                if (alignment & alignLeft) xpos = x + symwidth0 - 1;
                else if (alignment & alignRight) xpos = x + w - symwidth1 - strw - imgw0 - 1;
                else xpos = x + (w - strw - symtotal - imgw0) / 2 - 1;
            }
            int yimg;
            if (alignment & alignTop) yimg = ypos - lineHeight;
            else if (alignment & alignBottom) yimg = ypos - lineHeight + strh - img.h() - 1;
            else yimg = ypos - lineHeight + (strh - img.h() - 1) / 2;
            img.draw(xpos, yimg);
        }

        // Now draw all the text lines. Ported from FLTK's own
        // `for (p=str; ; ypos += height) { ...; if (!*e || ...) break;
        // p = e; }` (src/fl_draw.cxx) -- in C, `break`ing out of a
        // `for(;;increment)` loop skips that iteration's increment
        // clause, so FLTK's `ypos` is advanced by `height` only
        // *between* lines, never after the last one (for a single-line
        // label -- the common case -- `ypos` isn't advanced at all).
        // The increment is therefore gated on `i > 0` here (advancing
        // *before* drawing every line but the first) rather than
        // unconditionally after every line as a plain `foreach` would
        // -- an unconditional trailing `ypos += lineHeight` would silently
        // add one whole extra line's worth of vertical space after
        // the text, which only becomes visible where something reads
        // `ypos` afterward: an `alignTextOverImage` image drawn below
        // the text (the "image above text" case draws its image
        // *before* this loop runs, so it isn't affected). `test/bitmap.d`'s "text over"
        // mode exercises this: the image would otherwise sit visibly detached from its label by a
        // full extra line height, instead of directly beneath it as in
        // real FLTK.
        foreach (i, line; lines)
        {
            if (i > 0) ypos += lineHeight;

            int lw = cast(int)(width(line) + 0.5);
            int xpos;
            if (alignment & alignLeft)
                xpos = x + symwidth0 + imgw0;
            else if (alignment & alignRight)
                xpos = x + w - lw - symwidth1 - imgw1;
            else
                xpos = x + (w - lw - symtotal - imgw0 - imgw1) / 2 + symwidth0 + imgw0;

            callthis(line, cast(int) line.length, xpos, ypos - desc);

            // Underline: matches FLTK's own trick (expand_text_()/
            // fl_draw(), src/fl_draw.cxx) of drawing a literal "_"
            // glyph at the same baseline right before the marked
            // character, rather than a separate line primitive.
            if (underlineAt[i] >= 0)
            {
                int underlineX = xpos + cast(int)(width(line[0 .. underlineAt[i]]) + 0.5);
                callthis("_", 1, underlineX, ypos - desc);
            }
        }

        // Draw the image if it's *below* the text.
        if (img !is null && imgvert && (alignment & alignTextOverImage))
        {
            if (img.w() > symoffset) symoffset = img.w();
            int xpos;
            if (alignment & alignLeft) xpos = x + symwidth0;
            else if (alignment & alignRight) xpos = x + w - img.w() - symwidth1;
            else xpos = x + (w - img.w() - symtotal) / 2 + symwidth0;
            img.draw(xpos, ypos + spacing);
        }

        // Draw the symbols themselves, if any -- ported from fl_draw()'s
        // own tail (src/fl_draw.cxx), after everything else so they
        // layer on top like FLTK.
        if (symwidth0)
        {
            int xpos, ySym;
            if (alignment & alignLeft) xpos = x;
            else if (alignment & alignRight) xpos = x + w - symtotal - symoffset;
            else xpos = x + (w - symoffset - symtotal) / 2;

            if (alignment & alignBottom) ySym = y + h - symwidth0;
            else if (alignment & alignTop) ySym = y;
            else ySym = y + (h - symwidth0) / 2;

            drawSymbol(detected.leadSymbol, xpos, ySym, symwidth0, symwidth0, fl_color());
        }
        if (symwidth1)
        {
            int xpos, ySym;
            if (alignment & alignLeft) xpos = x + symoffset + symwidth0;
            else if (alignment & alignRight) xpos = x + w - symwidth1;
            else xpos = x + (w - symoffset - symtotal) / 2 + symoffset + symwidth0;

            if (alignment & alignBottom) ySym = y + h - symwidth1;
            else if (alignment & alignTop) ySym = y;
            else ySym = y + (h - symwidth1) / 2;

            drawSymbol(detected.trailSymbol, xpos, ySym, symwidth1, symwidth1, fl_color());
        }
    }

    /// Height (in pixels) of a line of text in (face, size) -- opens/
    /// caches that font without disturbing the current fl_font().
    ///
    /// Must NOT return the raw `XftFont.height` field: FLTK's
    /// own `Fl_Xlib_Graphics_Driver::height_unscaled()` (the non-Pango
    /// Xft build this port emulates, `Fl_Xlib_Graphics_Driver_font_xft.cxx`)
    /// deliberately does *not* use that field -- it returns `font->ascent
    /// + font->descent` instead. Xft's own `height` field bakes in each
    /// font's internal recommended line-gap/leading on top of
    /// ascent+descent, which is often noticeably larger; FLTK's
    /// choice to skip it is what makes FLTK's own line spacing tighter
    /// than "the font's own suggested leading" would produce. Every
    /// consumer of `height()` in this port (`fl.terminal`'s
    /// `fontheight_`, `Widget.drawLabel()`'s line-wrapping, etc.)
    /// depends on getting the tighter value, matching FLTK's own line
    /// count for the same box height.
    /// `size` is a FLTK-unit size; the font is looked up/opened at
    /// `size * currentScale()` device pixels and the result divided
    /// back down, matching `fl_font()`'s own scaling so this always
    /// agrees with `height()` for the current
    /// font -- ported from `Fl_Scalable_Graphics_Driver::height()`'s
    /// `int(height_unscaled()/scale())` pattern.
    int height(Font face, Fontsize size)
    {
        float s = currentScale();
        int devSize = cast(int)(size * s);
        if (devSize < 1) devSize = 1;
        auto f = xftFontFor(face, cast(Fontsize) devSize);
        return f !is null ? cast(int)((f.ascent + f.descent) / s) : size + 4;
    }

    /// ditto, for the current fl_font().
    int height()
    {
        return height(currentFontFace_, currentFontSize_);
    }

    /// Descent (in pixels, below the baseline) of the current fl_font().
    /// `currentXftFont_` is already open at the scaled device size (see
    /// `fl_font()`), so its `descent` field is divided back down to
    /// FLTK units here, matching `Fl_Scalable_Graphics_Driver::descent()`.
    int descent()
    {
        return currentXftFont_ !is null
            ? cast(int)(currentXftFont_.descent / currentScale()) : 4;
    }

    /// Width (in pixels) of nChars characters of str in the current
    /// fl_font(). Divided back down from the scaled device font's real
    /// measurement to FLTK units, matching
    /// `Fl_Scalable_Graphics_Driver::width()`.
    double width(const(char)[] str, int nChars)
    {
        if (currentXftFont_ is null || nChars <= 0) return nChars * 6.0;
        XGlyphInfo extents;
        XftTextExtentsUtf8(display_, currentXftFont_, cast(const(ubyte)*) str.ptr, nChars, &extents);
        return extents.xOff / currentScale();
    }

    /// ditto, measuring the whole string.
    double width(const(char)[] str)
    {
        return width(str, cast(int) str.length);
    }

    /**
     * Returns the exact bounding box (dx, dy, w, h) of nChars characters
     * of str, relative to the pen position, in the current fl_font() --
     * the *tight* glyph bounding box, unlike fl_measure()'s typographical
     * advance-based extents (which include a font's designed inter-line
     * leading/whitespace). Ported from
     * `Fl_Xlib_Graphics_Driver::text_extents_unscaled()`
     * (`src/drivers/Xlib/Fl_Xlib_Graphics_Driver_font_xft.cxx`): a
     * straight `XftTextExtentsUtf8()` glyph-ink query, same primitive
     * `width()` already uses above. Divided back down from the scaled
     * device font's real measurement to FLTK units, matching
     * `Fl_Scalable_Graphics_Driver::text_extents()`'s own
     * `int(x/scale())`-style divisions.
     */
    void textExtents(const(char)[] str, int nChars, out int dx, out int dy, out int w, out int h)
    {
        if (currentXftFont_ is null || nChars <= 0)
        {
            dx = dy = w = h = 0;
            return;
        }
        XGlyphInfo extents;
        XftTextExtentsUtf8(display_, currentXftFont_, cast(const(ubyte)*) str.ptr, nChars, &extents);
        float s = currentScale();
        w = cast(int)(extents.width / s);
        h = cast(int)(extents.height / s);
        dx = cast(int)(-extents.x / s);
        dy = cast(int)(-extents.y / s);
    }

    /// ditto, measuring the whole string.
    void textExtents(const(char)[] str, out int dx, out int dy, out int w, out int h)
    {
        textExtents(str, cast(int) str.length, dx, dy, w, h);
    }

    /**
     * Draws n bytes of str right-to-left, ending at (x, y) -- i.e. the
     * string's right edge sits at x, matching FLTK's own doc
     * comment ("Draw a UTF-8 string ... right to left starting at the
     * given x, y location"). Ported from
     * `Fl_Xlib_Graphics_Driver::rtl_draw_unscaled()`: decodes str's
     * codepoints, reverses their *order* (not a byte-reversal -- that
     * would produce invalid UTF-8, FLTK's own comment on why),
     * re-encodes, then draws the reversed string left-to-right at
     * `x - width`. This is glyph-order reversal only, not real
     * bidirectional text shaping (matching FLTK exactly -- neither
     * this port nor FLTK's Xft driver does real BiDi).
     */
    void rtlDraw(const(char)[] str, int n, int x, int y)
    {
        import fl.text_buffer : utf8DecodeAt, utf8Encode;
        import std.algorithm.mutation : reverse;

        if (n > str.length) n = cast(int) str.length;

        uint[] codepoints;
        size_t i = 0;
        while (i < n)
        {
            int len;
            codepoints ~= utf8DecodeAt(str, i, len);
            i += len;
        }
        codepoints.reverse();

        char[] buf;
        buf.reserve(codepoints.length * 4);
        char[4] enc;
        foreach (cp; codepoints)
            buf ~= enc[0 .. utf8Encode(cp, enc[])];

        double w = width(buf, cast(int) buf.length);
        fl_draw(cast(string) buf, cast(int)(x - w), y);
    }
}
else
{
    // ---- Shared compositions ----
    //
    // Copied verbatim from the `version (linux)` block above: none of
    // these touch Xft/GDI directly -- they're pure layout/dispatch,
    // built from the per-platform leaf functions below (`fl_font()`,
    // the already-unconditional 3-arg `fl_draw(str,nChars,x,y)` leaf,
    // `height()`, `descent()`, `width()`) plus already-unconditional
    // helpers (`pushClip()`/`popClip()`, `wrapLine()`,
    // `stripShortcutMarker()`, `detectSymbols()`, `drawSymbol()`), so
    // one copy correctly serves every non-Linux platform. Kept as a
    // literal copy here rather than hoisted to true top-level scope
    // shared with the `version (linux)` block too, specifically to
    // avoid touching that already-tested code at all for this change --
    // see each function's `version (linux)` twin for the full doc
    // comment (FLTK source references, algorithm notes); comments
    // here are trimmed to avoid drift between two copies of the same
    // prose.

    void fl_draw(const(char)[] str, int x, int y)
    {
        fl_draw(str, cast(int) str.length, x, y);
    }

    void fl_draw(int angle, const(char)[] str, int nChars, int x, int y)
    {
        if (currentDriver !is null)
        {
            currentDriver.draw(angle, str, nChars, x, y);
            return;
        }
        fl_draw(str, nChars, x, y);
    }

    /// ditto, the plain no-length form.
    void fl_draw(int angle, const(char)[] str, int x, int y)
    {
        fl_draw(angle, str, cast(int) str.length, x, y);
    }

    /// Draws str aligned within (x,y,w,h) -- a thin convenience forward
    /// to the image-aware overload below with no image.
    void fl_draw(string str, int x, int y, int w, int h, Align alignment)
    {
        fl_draw(str, x, y, w, h, alignment, null, 0);
    }

    /// The per-line text-drawing hook `fl_draw(str,x,y,w,h,align,
    /// callthis,img,spacing)` below calls instead of drawing directly.
    alias DrawTextCb = void delegate(const(char)[] str, int n, int x, int y);

    /// ditto, defaulting `callthis` to a closure over the plain
    /// `fl_draw(str,n,x,y)` primitive above.
    void fl_draw(string str, int x, int y, int w, int h, Align alignment, Image img, int spacing = 0,
        bool drawSymbols = true)
    {
        fl_draw(str, x, y, w, h, alignment,
            (const(char)[] s, int n, int X, int Y) { fl_draw(s, n, X, Y); }, img, spacing, drawSymbols);
    }

    /// ditto, the real implementation -- draws str aligned within
    /// (x,y,w,h), plus img composed alongside it per alignment.
    void fl_draw(string str, int x, int y, int w, int h, Align alignment, DrawTextCb callthis, Image img, int spacing = 0,
        bool drawSymbols = true)
    {
        if (str.length == 0 && img is null) return;
        if (img !is null && (alignment & alignImageBackdrop)) img = null;
        if (alignment & alignClip) pushClip(x, y, w, h);
        scope(exit) if (alignment & alignClip) popClip();

        int lineHeight = height();
        int desc = descent();

        bool imgvert = (alignment & alignImageNextToText) == 0; // true: image above/below text
        int imgtotal = (img !is null && !imgvert) ? img.w() + spacing : 0;

        // drawSymbols false (FLTK's draw_symbols = 0, e.g. Fl_Browser's
        // item text): no symbols, and '@@' stays as written.
        auto detected = drawSymbols ? detectSymbols(str) : SymbolSplit(str);
        const(char)[] textOnly = drawSymbols ? unescapeAtSymbols(detected.text) : detected.text;
        int symwidth0 = detected.leadSymbol.length ? (w < h ? w : h) : 0;
        int symwidth1 = detected.trailSymbol.length ? (w < h ? w : h) : 0;
        int symtotal = symwidth0 + symwidth1;

        const(char)[][] lines;
        ptrdiff_t[] underlineAt;

        void addLine(const(char)[] rawLine, int wrapBudget)
        {
            ptrdiff_t ul;
            string stripped = stripShortcutMarker(rawLine.idup, ul);
            if (alignment & alignWrap)
            {
                foreach (sub; wrapLine(stripped, wrapBudget))
                {
                    size_t offset = sub.ptr - stripped.ptr;
                    lines ~= sub;
                    underlineAt ~= (ul >= 0 && ul >= offset && ul < offset + sub.length)
                        ? ul - offset : -1;
                }
            }
            else
            {
                lines ~= stripped;
                underlineAt ~= ul;
            }
        }

        void buildLines(int wrapBudget)
        {
            lines = null;
            underlineAt = null;
            foreach (rawLine; splitTextLines(textOnly))
                addLine(rawLine, wrapBudget);
        }

        buildLines(w - imgtotal - symtotal);
        int nLines = str is null ? 0 : cast(int) lines.length;

        if (nLines > 0)
        {
            if (symwidth0) symwidth0 = nLines * lineHeight;
            if (symwidth1) symwidth1 = nLines * lineHeight;
        }
        int newSymtotal = symwidth0 + symwidth1;
        if (newSymtotal != symtotal)
        {
            symtotal = newSymtotal;
            buildLines(w - imgtotal - symtotal);
            nLines = cast(int) lines.length;
        }

        int strw = 0;
        foreach (line; lines)
        {
            int lw = cast(int)(width(line) + 0.5);
            if (lw > strw) strw = lw;
        }
        int symoffset = strw; // FLTK's own "widest text line" stand-in

        int strh = nLines * lineHeight;
        int imgh = (img !is null && imgvert) ? img.h() + spacing : 0;

        int ypos;
        if (alignment & alignBottom)
            ypos = y + h - (nLines - 1) * lineHeight - imgh;
        else if (alignment & alignTop)
            ypos = y + lineHeight;
        else
            ypos = y + (h - nLines * lineHeight - imgh) / 2 + lineHeight;

        // Draw the image if located *above* the text.
        if (img !is null && imgvert && !(alignment & alignTextOverImage))
        {
            if (img.w() > symoffset) symoffset = img.w();
            int xpos;
            if (alignment & alignLeft) xpos = x + symwidth0;
            else if (alignment & alignRight) xpos = x + w - img.w() - symwidth1;
            else xpos = x + (w - img.w() - symtotal) / 2 + symwidth0;
            img.draw(xpos, ypos - lineHeight);
            ypos += img.h() + spacing;
        }

        // Draw the image if either on the *left* or *right* of the text.
        int imgw0 = 0, imgw1 = 0;
        if (img !is null && !imgvert)
        {
            int xpos;
            if (alignment & alignTextOverImage)
            {
                // Image to the right of the text.
                imgw1 = img.w() + spacing;
                if (alignment & alignLeft) xpos = x + symwidth0 + strw + 1;
                else if (alignment & alignRight) xpos = x + w - symwidth1 - imgw1 + 1;
                else xpos = x + (w - strw - symtotal - imgw1) / 2 + symwidth0 + strw + 1;
                xpos += spacing;
            }
            else
            {
                // Image to the left of the text.
                imgw0 = img.w() + spacing;
                if (alignment & alignLeft) xpos = x + symwidth0 - 1;
                else if (alignment & alignRight) xpos = x + w - symwidth1 - strw - imgw0 - 1;
                else xpos = x + (w - strw - symtotal - imgw0) / 2 - 1;
            }
            int yimg;
            if (alignment & alignTop) yimg = ypos - lineHeight;
            else if (alignment & alignBottom) yimg = ypos - lineHeight + strh - img.h() - 1;
            else yimg = ypos - lineHeight + (strh - img.h() - 1) / 2;
            img.draw(xpos, yimg);
        }

        foreach (i, line; lines)
        {
            if (i > 0) ypos += lineHeight;

            int lw = cast(int)(width(line) + 0.5);
            int xpos;
            if (alignment & alignLeft)
                xpos = x + symwidth0 + imgw0;
            else if (alignment & alignRight)
                xpos = x + w - lw - symwidth1 - imgw1;
            else
                xpos = x + (w - lw - symtotal - imgw0 - imgw1) / 2 + symwidth0 + imgw0;

            callthis(line, cast(int) line.length, xpos, ypos - desc);

            if (underlineAt[i] >= 0)
            {
                int underlineX = xpos + cast(int)(width(line[0 .. underlineAt[i]]) + 0.5);
                callthis("_", 1, underlineX, ypos - desc);
            }
        }

        // Draw the image if it's *below* the text.
        if (img !is null && imgvert && (alignment & alignTextOverImage))
        {
            if (img.w() > symoffset) symoffset = img.w();
            int xpos;
            if (alignment & alignLeft) xpos = x + symwidth0;
            else if (alignment & alignRight) xpos = x + w - img.w() - symwidth1;
            else xpos = x + (w - img.w() - symtotal) / 2 + symwidth0;
            img.draw(xpos, ypos + spacing);
        }

        // Draw the symbols themselves, if any.
        if (symwidth0)
        {
            int xpos, ySym;
            if (alignment & alignLeft) xpos = x;
            else if (alignment & alignRight) xpos = x + w - symtotal - symoffset;
            else xpos = x + (w - symoffset - symtotal) / 2;

            if (alignment & alignBottom) ySym = y + h - symwidth0;
            else if (alignment & alignTop) ySym = y;
            else ySym = y + (h - symwidth0) / 2;

            drawSymbol(detected.leadSymbol, xpos, ySym, symwidth0, symwidth0, fl_color());
        }
        if (symwidth1)
        {
            int xpos, ySym;
            if (alignment & alignLeft) xpos = x + symoffset + symwidth0;
            else if (alignment & alignRight) xpos = x + w - symwidth1;
            else xpos = x + (w - symoffset - symtotal) / 2 + symoffset + symwidth0;

            if (alignment & alignBottom) ySym = y + h - symwidth1;
            else if (alignment & alignTop) ySym = y;
            else ySym = y + (h - symwidth1) / 2;

            drawSymbol(detected.trailSymbol, xpos, ySym, symwidth1, symwidth1, fl_color());
        }
    }

    /// ditto, measuring the whole string.
    double width(const(char)[] str)
    {
        return width(str, cast(int) str.length);
    }

    /// ditto, measuring the whole string.
    void textExtents(const(char)[] str, out int dx, out int dy, out int w, out int h)
    {
        textExtents(str, cast(int) str.length, dx, dy, w, h);
    }

    /// Draws n bytes of str right-to-left, ending at (x, y) -- glyph-
    /// order reversal only, not real bidirectional shaping (matching
    /// FLTK's own Xft driver exactly).
    void rtlDraw(const(char)[] str, int n, int x, int y)
    {
        import fl.text_buffer : utf8DecodeAt, utf8Encode;
        import std.algorithm.mutation : reverse;

        if (n > str.length) n = cast(int) str.length;

        uint[] codepoints;
        size_t i = 0;
        while (i < n)
        {
            int len;
            codepoints ~= utf8DecodeAt(str, i, len);
            i += len;
        }
        codepoints.reverse();

        char[] buf;
        buf.reserve(codepoints.length * 4);
        char[4] enc;
        foreach (cp; codepoints)
            buf ~= enc[0 .. utf8Encode(cp, enc[])];

        double w = width(buf, cast(int) buf.length);
        fl_draw(cast(string) buf, cast(int)(x - w), y);
    }

    // ---- Per-platform leaves ----

    version (Windows)
    {
        import core.sys.windows.windows;
        import std.utf : toUTF16z, toUTF8;

        /// Ported from the file-scope `enumcbw()` callback
        /// (`Fl_GDI_Graphics_Driver_font.cxx`) -- registers one, two, or
        /// four synthetic style variants (plain/bold/italic/bold-italic)
        /// of `lpelf`'s face name as new custom font slots, skipping
        /// faces that already match one of the 16 built-ins. **A real,
        /// faithfully-ported FLTK quirk, not a transcription
        /// mistake**: the bold/bold-italic variants are only registered
        /// when `lpelf.lfWeight <= 400` (normal-or-lighter) -- i.e. when
        /// enumeration hands us a face's *regular* weight, both a plain
        /// and a GDI-synthesized-bold variant are registered from it;
        /// when enumeration separately hands us that same family's own
        /// true "Bold" sub-face (`lfWeight` > 400), only plain/italic get
        /// (re-)registered for *that* entry, avoiding a duplicate
        /// synthesized-bold registration on top of a real one.
        private extern (Windows) int enumFontsCallback(const(LOGFONTW)* lpelf,
            const(TEXTMETRICW)* lpntm, DWORD fontType, LPARAM p) nothrow
        {
            try
            {
                if (p == 0 && lpelf.lfCharSet != ANSI_CHARSET) return 1;

                size_t nameLen = 0;
                while (nameLen < lpelf.lfFaceName.length && lpelf.lfFaceName[nameLen] != 0) nameLen++;
                string family = lpelf.lfFaceName[0 .. nameLen].toUTF8;

                foreach (i; 0 .. freeFont)
                {
                    string existing = getFont(i);
                    if (existing.length > 1 && existing[1 .. $] == family) return 1;
                }

                void registerVariant(char styleChar)
                {
                    setFont(nextFreeFont_, cast(string)(styleChar ~ family));
                    nextFreeFont_++;
                }

                registerVariant(' ');
                if (lpelf.lfWeight <= 400) registerVariant('B');
                registerVariant('I');
                if (lpelf.lfWeight <= 400) registerVariant('P');
            }
            catch (Exception)
            {
            }
            return 1;
        }

        /// Shared state between `getFontSizes()` and `enumSizesCallback()`
        /// below -- matches FLTK's own file-scope `nbSize`/
        /// `cyPerInch`/`sizes[128]` statics (`Fl_GDI_Graphics_Driver_
        /// font.cxx`), as a growable array rather than a fixed 128-entry
        /// one (nothing this port does needs that specific cap).
        private int[] fontSizesCollected_;
        private int fontSizeCyPerInch_ = 1;

        /// Ported from the file-scope `EnumSizeCbW()` callback -- stops
        /// enumeration immediately (returning `0`) the moment a scalable
        /// (non-raster) font is seen, matching FLTK's own "claim the
        /// whole family is scalable" shortcut; otherwise inserts this
        /// raster size into `fontSizesCollected_`, sorted, de-duplicated.
        private extern (Windows) int enumSizesCallback(const(LOGFONTW)* lpelf,
            const(TEXTMETRICW)* lpntm, DWORD fontType, LPARAM p) nothrow
        {
            if ((fontType & RASTER_FONTTYPE) == 0)
            {
                fontSizesCollected_ = [0];
                return 0;
            }

            int add = lpntm.tmHeight - lpntm.tmInternalLeading;
            add = MulDiv(add, 72, fontSizeCyPerInch_);

            size_t start = 0;
            while (start < fontSizesCollected_.length && fontSizesCollected_[start] < add) start++;
            if (start < fontSizesCollected_.length && fontSizesCollected_[start] == add) return 1;

            fontSizesCollected_.length = fontSizesCollected_.length + 1;
            for (size_t i = fontSizesCollected_.length - 1; i > start; i--)
                fontSizesCollected_[i] = fontSizesCollected_[i - 1];
            fontSizesCollected_[start] = add;

            return fontSizesCollected_.length < 128 ? 1 : 0;
        }

        /// Ported from `Fl_GDI_Graphics_Driver::font_unscaled()`, via
        /// `fl.gdi_graphics_driver.GdiGraphicsDriver.selectFont()` (see
        /// that method's own doc comment).
        void fl_font(Font face, Fontsize size)
        {
            if (auto gdi = cast(GdiGraphicsDriver) currentDriver)
                gdi.selectFont(face, size);
        }

        /// Height (in pixels) of a line of text in (face, size) --
        /// opens/caches that font without disturbing the current
        /// `fl_font()`, via `GdiGraphicsDriver.heightFor()`.
        int height(Font face, Fontsize size)
        {
            auto gdi = cast(GdiGraphicsDriver) currentDriver;
            return gdi !is null ? gdi.heightFor(face, size) : size + 4;
        }

        /// ditto, for the current fl_font().
        int height()
        {
            auto gdi = cast(GdiGraphicsDriver) currentDriver;
            return gdi !is null ? gdi.fontHeight() : height(0, 14);
        }

        /// Descent (in pixels, below the baseline) of the current
        /// fl_font().
        int descent()
        {
            auto gdi = cast(GdiGraphicsDriver) currentDriver;
            return gdi !is null ? gdi.fontDescent() : 4;
        }

        /// Width (in pixels) of nChars characters of str in the current
        /// fl_font(), via `GdiGraphicsDriver.textWidth()` (a full port of
        /// FLTK's own multi-vs-single-codepoint split and per-
        /// codepoint width cache -- see that method's own doc comment).
        double width(const(char)[] str, int nChars)
        {
            auto gdi = cast(GdiGraphicsDriver) currentDriver;
            return gdi !is null ? gdi.textWidth(str, nChars) : nChars * 6.0;
        }

        /// Returns the tight, glyph-ink bounding box (dx, dy, w, h) of
        /// nChars characters of str, relative to the pen position, via
        /// `GdiGraphicsDriver.textExtents()` (a full port of FLTK's
        /// real `GetGlyphIndicesW()`/`GetGlyphOutlineW()` path, including
        /// its own `GetCharacterPlacementW()` surrogate-pair fallback and
        /// further `exit_error:` degraded fallback -- see that method's
        /// own doc comment).
        void textExtents(const(char)[] str, int nChars, out int dx, out int dy, out int w, out int h)
        {
            auto gdi = cast(GdiGraphicsDriver) currentDriver;
            if (gdi !is null)
            {
                gdi.textExtents(str, nChars, dx, dy, w, h);
                return;
            }
            int lineHeight = height();
            w = cast(int) width(str, nChars);
            h = lineHeight;
            dx = 0;
            dy = descent() - lineHeight;
        }

        /**
         * Adds every font `EnumFontFamiliesW()` enumerates to the
         * custom-font range (`freeFont` and up) -- ported from
         * `Fl_GDI_Graphics_Driver::set_fonts()`/the file-scope
         * `enumcbw()` callback (`Fl_GDI_Graphics_Driver_font.cxx`).
         * `xstarname` is accepted for API parity with the Linux overload
         * but, matching FLTK's own behavior exactly (`EnumFontFamiliesW
         * (gc, NULL, enumcbw, xstarname != 0)` -- the enumerated *face*
         * filter is always `NULL`, only the callback's own `ANSI_CHARSET`
         * skip is toggled by whether a name was passed at all), doesn't
         * otherwise filter by it.
         */
        Font setFonts(string pattern = "*")
        {
            if (nextFreeFont_ > freeFont) return nextFreeFont_; // already been here, matches FLTK's own guard

            HDC gc = GetDC(null);
            scope (exit) ReleaseDC(null, gc);
            EnumFontFamiliesW(gc, null, &enumFontsCallback, pattern.length ? 1 : 0);
            return nextFreeFont_;
        }

        /**
         * Returns every fixed raster size `EnumFontFamiliesW()` lists for
         * `fnum`'s family via `sizes` -- `[0]` alone means "scalable"
         * (works at any size, matching FLTK's own convention for
         * outline/TrueType fonts, the overwhelming majority on any real
         * system). Ported from `Fl_GDI_Graphics_Driver::get_font_sizes()`/
         * the file-scope `EnumSizeCbW()` callback.
         */
        int getFontSizes(Font fnum, out int[] sizes)
        {
            string raw = getFont(fnum);
            char c0 = raw.length > 0 ? raw[0] : ' ';
            bool recognized = c0 == ' ' || c0 == 'B' || c0 == 'I' || c0 == 'P';
            string family = (recognized && raw.length > 0) ? raw[1 .. $] : raw;

            HDC gc = GetDC(null);
            scope (exit) ReleaseDC(null, gc);
            fontSizeCyPerInch_ = GetDeviceCaps(gc, LOGPIXELSY);
            if (fontSizeCyPerInch_ < 1) fontSizeCyPerInch_ = 1;
            fontSizesCollected_.length = 0;

            EnumFontFamiliesW(gc, family.toUTF16z, &enumSizesCallback, 0);

            sizes = fontSizesCollected_.dup;
            return cast(int) sizes.length;
        }
    }
    else
    {
        /// Fallback for platforms without a backend: sets the font/size used by subsequent fl_draw() text
        /// calls, forwarding to the graphics driver FLTK. No-op on
        /// platforms with no driver yet.
        void fl_font(Font face, Fontsize size)
        {
        }

        /// Fallback for platforms without a backend: returns the height (in pixels) of a line of text in
        /// (face, size). No font metrics exist on such a platform, so
        /// this returns a fixed "size + 4" placeholder.
        int height(Font face, Fontsize size)
        {
            return size + 4;
        }

        /// ditto, for the current fl_font().
        int height()
        {
            return height(0, 14);
        }

        /// Fallback for platforms without a backend: returns the descent (in pixels, below the baseline) of
        /// the font set by the most recent fl_font() call. Fixed
        /// placeholder on this platform.
        int descent()
        {
            return 4;
        }

        /// Fallback for platforms without a backend: returns the width (in pixels) of nChars characters of
        /// str in the font set by the most recent fl_font() call.
        /// Fixed-width-per-byte placeholder (6px, matching FLTK's
        /// own TMPFONTWIDTH stand-in) on this platform.
        double width(const(char)[] str, int nChars)
        {
            return nChars * 6.0;
        }

        /// Fallback for platforms without a backend: returns the exact glyph bounding box of nChars
        /// characters of str. Fixed placeholder (zeroed) on this
        /// platform.
        void textExtents(const(char)[] str, int nChars, out int dx, out int dy, out int w, out int h)
        {
            dx = dy = w = h = 0;
        }
    }
}

/// Draws nChars of str at (x,y), baseline-positioned, in the current
/// fl_font()/fl_color() -- the low-level primitive the aligned/multi-
/// line fl_draw() overload calls once per line. Dispatches to
/// `fl.graphics_driver.currentDriver` first when one is active;
/// otherwise real on Linux via Xft. Pulled out of the shared
/// `version(linux){}`/`else{}` block above into its own top-level
/// function (same treatment as `fl.draw`'s other dispatched leaves) so
/// the dispatch check has one call site regardless of platform, even
/// though every *other* text function stays inside that shared block
/// (none of them are leaves -- see this module's own top comment).
/// (x,y) is the FLTK-unit pen position, scaled via `scaledFloor()`
/// before drawing -- `currentXftFont_`
/// itself is already open at the scaled device size (see `fl_font()`),
/// so the glyphs come out the right size; only the pen position needed
/// this. Ported from `Fl_Scalable_Graphics_Driver::draw()`'s
/// `draw_unscaled(str, n, floor(x), floor(y + offset))`, including its
/// `offset = (scale() == 1 ? 0 : -1)` pixel nudge (FLTK's own
/// comment: "for issue #1308") -- a 1-FLTK-unit baseline adjustment
/// applied only when scale isn't exactly 1, folded into the same
/// `scaledFloor()` call `y` alone already needed rather than a second
/// rounding step.
///
/// Without this nudge, every label's text would sit a uniform 1
/// device pixel lower than real FLTK's own at any scale other than
/// 1.0 (measured via
/// a pixel-identical-except-for-a-1-row-shift comparison against a
/// same-driver, non-Cairo/non-Pango FLTK build). This nudge is exactly what FLTK uses to compensate
/// for that same class of scale-rounding drift.
void fl_draw(const(char)[] str, int nChars, int x, int y)
{
    if (currentDriver !is null)
    {
        currentDriver.draw(str, nChars, x, y);
        return;
    }
    version (linux)
    {
        if (xftDraw_ is null || currentXftFont_ is null || nChars <= 0) return;
        XftColor col = xftColorFor(currentColor_);
        scope(exit) XftColorFree(display_, visual_, colormap_, &col);
        int offset = currentScale() == 1f ? 0 : -1;
        XftDrawStringUtf8(xftDraw_, &col, currentXftFont_,
            scaledFloor(x) + offsetX_, scaledFloor(y + offset) + offsetY_,
            cast(const(ubyte)*) str.ptr, nChars);
    }
}

/// Returns the font face last set via `fl_font()` -- ported from
/// FLTK's own `Fl_Font fl_font()` getter (`FL/fl_draw.H`), not
/// previously ported. Needed by `fl.svg_file_surface.SvgGraphicsDriver.
/// draw()` to map the *current* font to an SVG `font-family` at the
/// point text is actually emitted (text metrics/font selection are
/// deliberately never dispatched -- see `fl.graphics_driver.
/// GraphicsDriver`'s own doc comment -- so this always reads the one
/// real, native font state, regardless of which driver is current).
Font fl_font()
{
    version (linux) return currentFontFace_;
    else return 0;
}

/// ditto, the current font size. Ported from FLTK's own
/// `Fl_Fontsize fl_size()` getter.
Fontsize fl_size()
{
    version (linux) return currentFontSize_;
    else return 14;
}

/**
 * Measures the size str would need to draw at, in the current
 * fl_font(). `w` is an in/out parameter, matching FLTK's own
 * `fl_measure()` convention exactly: pass it as `0` for a plain
 * "natural size" measurement (the width of str's widest '\n'-separated
 * line, no wrapping), or preset it to a desired wrap width to get real
 * word-wrap -- each '\n'-separated line is then wrapped to fit that
 * width via wrapLine() (same rule as fl_draw()'s alignWrap: breaks
 * only at word boundaries, a single overlong word is never split), and
 * on return `w` holds the actual widest *wrapped* line's width (at or
 * under the input value) while `h` accounts for every wrapped line,
 * not just the '\n'-separated ones. Callers that want the old
 * behavior just keep passing a freshly-declared `int` (D
 * default-initializes it to `0`).
 *
 * `drawSymbols` is FLTK's `draw_symbols` (default 1): false measures
 * str as plain text, with no '@'-symbols and '@@' left as written,
 * matching fl_draw()'s own `drawSymbols`.
 */
void fl_measure(const(char)[] str, ref int w, out int h, bool drawSymbols = true)
{
    if (str.length == 0) { w = 0; h = 0; return; }

    int lineHeight = height();

    // Leading/trailing '@'-symbol detection -- **not** detectSymbols()
    // (fl_draw()'s version): FLTK's own fl_measure() (src/
    // fl_draw.cxx) uses a genuinely different, inconsistent rule for
    // the trailing symbol (first '@' via strchr(), weaker guard) than
    // fl_draw() does (last '@' via strrchr(), extra `p > str+1`/
    // `p[-1]!='@'` guards) -- a real FLTK discrepancy (the two
    // could disagree on a label containing more than one '@'), found
    // while porting and logged in FLTK_ISSUES.md rather than
    // silently unified; ported faithfully as two distinct functions,
    // matching each one's own real behavior.
    auto detected = drawSymbols ? detectSymbolsForMeasure(str) : SymbolSplit(str);
    const(char)[] textOnly = drawSymbols ? unescapeAtSymbols(detected.text) : detected.text;

    int symwidth0 = detected.leadSymbol.length ? lineHeight : 0;
    int symwidth1 = detected.trailSymbol.length ? lineHeight : 0;
    int symtotal = symwidth0 + symwidth1;

    int wrapWidth = w - symtotal;
    int maxw = 0;
    int lines = 0;

    void measureLine(const(char)[] rawLine)
    {
        // Strip the '&'-shortcut marker before measuring, matching
        // fl_draw()'s own buildLines()/addLine() -- FLTK's
        // fl_measure() feeds every line through the same expand_text_()
        // fl_draw() uses, which strips a lone '&' (never actually
        // printed -- it just marks the next character for underlining)
        // before computing its width. Skipping that step would make a "&File"-style label measure
        // one character too wide -- small per label, but compounding
        // across every "&"-shortcut item in a menu bar/dropdown into an
        // overflow (menubar.cxx's top-level row
        // running off the window's right edge).
        ptrdiff_t ul;
        string stripped = stripShortcutMarker(rawLine.idup, ul);
        foreach (sub; wrapLine(stripped, wrapWidth))
        {
            int lw = cast(int)(width(sub) + 0.5);
            if (lw > maxw) maxw = lw;
            lines++;
        }
    }

    foreach (rawLine; splitTextLines(textOnly))
        measureLine(rawLine);

    if ((symwidth0 || symwidth1) && lines)
    {
        if (symwidth0) symwidth0 = lines * lineHeight;
        if (symwidth1) symwidth1 = lines * lineHeight;
    }
    symtotal = symwidth0 + symwidth1;

    w = maxw + symtotal;
    h = lines * lineHeight;
}

/**
 * Intersects (x,y,w,h) with the current clip (if any) and reports
 * whether the result differs from the input (i.e. whether anything was
 * actually clipped away). Real -- ported from Fl_Xlib_Graphics_
 * Driver::clip_box(), specialized to a single rectangle the same way
 * notClipped() above is (see this section's comment for why that's
 * exactly as capable for this port).
 */
bool clipBox(int x, int y, int w, int h, out int X, out int Y, out int W, out int H)
{
    auto c = currentClip();
    if (!c.active)
    {
        X = x; Y = y; W = w; H = h;
        return false;
    }
    auto r = intersectClip(x, y, w, h, c);
    X = r.x; Y = r.y; W = r.w; H = r.h;
    return X != x || Y != y || W != w || H != h;
}

/// Draws a solid-filled rectangle in the current fl_color(). Dispatches
/// to `fl.graphics_driver.currentDriver` first when one is active;
/// otherwise real on Linux (XFillRectangle), adding the current
/// `offsetX_`/`offsetY_` (zero unless
/// `fl.widget_surface.WidgetSurface.translate()` is active). Coordinates
/// scaled via `scaledFloor()`, computing width/height as
/// `scaledFloor(x+w)-scaledFloor(x)` rather than `scaledFloor(w)` so
/// adjacent rects' scaled edges stay flush instead of drifting apart at
/// non-integer scales -- ported from `Fl_Scalable_Graphics_Driver::
/// rectf()`. No clip-stack consultation
/// in the native path beyond whatever's already on the GC (see
/// `Fl_Xlib_Graphics_Driver::rectf_unscaled()`, not fully ported).
void fl_rectf(int x, int y, int w, int h)
{
    if (currentDriver !is null)
    {
        currentDriver.rectf(x, y, w, h);
        return;
    }
    if (clipRectToCoordSpace(x, y, w, h)) return;
    version (linux)
    {
        int sx = scaledFloor(x), sy = scaledFloor(y);
        int sw = scaledFloor(x + w) - sx, sh = scaledFloor(y + h) - sy;
        if (gc_ !is null && drawable_ != 0 && sw > 0 && sh > 0)
            XFillRectangle(display_, drawable_, gc_, sx + offsetX_, sy + offsetY_, cast(uint) sw, cast(uint) sh);
    }
}

/// Draws an unfilled border *inside* (x,y,w,h), in the current
/// fl_color(). Dispatches to `fl.graphics_driver.currentDriver` first
/// when one is active; otherwise real on Linux (XDrawRectangle) --
/// ported from `Fl_Scalable_Graphics_Driver::rect()`/`Fl_Xlib_Graphics_
/// Driver::rect_unscaled()` collapsed into one, same
/// `scaledFloor(x+w)-scaledFloor(x)` edge-alignment trick `fl_rectf()`
/// uses, minus a half-line-width inset (`d = int(currentScale())/2`) so
/// the border stays centered on the scaled boundary -- at `currentScale()
/// == 1` this reduces exactly to the pre-scaling `w-1`/`h-1` formula.
void fl_rect(int x, int y, int w, int h)
{
    if (currentDriver !is null)
    {
        currentDriver.rect(x, y, w, h);
        return;
    }
    version (linux)
    {
        if (gc_ !is null && drawable_ != 0 && w > 0 && h > 0)
        {
            int s = cast(int) currentScale();
            int d = s / 2;
            int rx = scaledFloor(x) + d, ry = scaledFloor(y) + d;
            int rw = scaledFloor(x + w) - scaledFloor(x) - s;
            int rh = scaledFloor(y + h) - scaledFloor(y) - s;
            if (rw > 0 && rh > 0)
                XDrawRectangle(display_, drawable_, gc_, rx + offsetX_, ry + offsetY_, cast(uint) rw, cast(uint) rh);
        }
    }
}

version (linux)
{
    /**
     * Scrolls the contents of (X,Y,W,H) by (dx,dy) pixels (via
     * XCopyArea() on the current drawable) and calls drawArea() for
     * each newly-exposed strip -- backs fl.scroll's incremental
     * scroll-and-patch redraw. Ported from fl_scroll() (src/
     * fl_scroll_area.cxx): the geometry math (which edge got exposed,
     * how much) is a faithful line-for-line port, collapsed into one
     * function rather than FLTK's split between the platform-
     * independent fl_scroll() and Fl_X11_Window_Driver::scroll() (no
     * driver abstraction exists in this port, see fl.platform_x11's own
     * "no abstraction until a second implementation needs one" note).
     * drawArea is a plain delegate rather than FLTK's
     * function-pointer+void* pair, per this project's usual callback
     * convention (see CONVENTIONS.md).
     *
     * Deliberately not ported: FLTK's driver-level `XWindowEvent()`
     * synchronous wait for `GraphicsExpose`/`NoExpose` after the
     * `XCopyArea()` call, which recovers pixels that were themselves
     * obscured by another window at the moment of the copy. This port's
     * shared GC has `graphics_exposures` disabled outright instead (see
     * `fl.platform_x11.openDisplay()`'s own comment on why a blocking
     * wait for a specific event type from inside a widget's `draw()`
     * call, nested inside this port's single `XNextEvent()` loop, isn't
     * worth the reentrancy risk for a rare edge case) -- so a scroll
     * while genuinely overlapped by another window can leave stale
     * pixels behind until the next full repaint, matching FLTK's
     * own documented caveat about `fl_scroll()` not being pixel-exact
     * in every case, just via a different (simpler, one-sided) tradeoff.
     */
    void fl_scroll(int X, int Y, int W, int H, int dx, int dy,
        void delegate(int, int, int, int) drawArea)
    {
        if (!dx && !dy) return;
        if (dx <= -W || dx >= W || dy <= -H || dy >= H)
        {
            // no intersection of old and new scroll -- everything is new
            drawArea(X, Y, W, H);
            return;
        }

        int srcX, srcW, destX, clipX, clipW;
        if (dx > 0)
        {
            srcX = X;
            destX = X + dx;
            srcW = W - dx;
            clipX = X;
            clipW = dx;
        }
        else
        {
            srcX = X - dx;
            destX = X;
            srcW = W + dx;
            clipX = X + srcW;
            clipW = W - srcW;
        }

        int srcY, srcH, destY, clipY, clipH;
        if (dy > 0)
        {
            srcY = Y;
            destY = Y + dy;
            srcH = H - dy;
            clipY = Y;
            clipH = dy;
        }
        else
        {
            srcY = Y - dy;
            destY = Y;
            srcH = H + dy;
            clipY = Y + srcH;
            clipH = H - srcH;
        }

        if (gc_ !is null && drawable_ != 0)
            XCopyArea(display_, drawable_, drawable_, gc_,
                srcX + offsetX_, srcY + offsetY_, cast(uint) srcW, cast(uint) srcH,
                destX + offsetX_, destY + offsetY_);

        if (dx) drawArea(clipX, destY, clipW, srcH);
        if (dy) drawArea(X, clipY, W, clipH);
    }
}
else
{
    /// Fallback for platforms without a backend: scrolls (X,Y,W,H) by (dx,dy) and calls drawArea() for the
    /// newly-exposed strips, forwarding to the graphics driver
    /// FLTK. No-op on non-Linux platforms.
    void fl_scroll(int X, int Y, int W, int H, int dx, int dy,
        void delegate(int, int, int, int) drawArea)
    {
    }
}

/// Sets the color to c, then draws an unfilled border inside
/// (x,y,w,h) -- the common "draw a rect outline in this color" idiom
/// FLTK's own inline wrapper exists for.
void fl_rect(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    fl_rect(x, y, w, h);
}

// ---------------------------------------------------------------------
// General line style (src/drivers/Xlib/Fl_Xlib_Graphics_Driver_line_style.cxx)
// ---------------------------------------------------------------------
//
// Real -- arbitrary dash pattern/width/
// line-cap/line-join for lineSolid/lineDash/lineDot/lineDashDot/
// lineDashDotDot, replacing focusRect()'s former hand-inlined
// XSetLineAttributes()/XSetDashes() calls (see that function's own doc
// comment below for the rewire). DELIBERATE SIMPLIFICATION: no *general*
// persistent `line_width_` driver
// state is tracked, unlike FLTK's Fl_Graphics_Driver -- nothing
// else in this port needs to query "what's the current line width"
// (focusRect() is the one caller that would care about *restoring*
// it; see that function's own doc comment for how it works around not
// having this state). One narrow, single-purpose
// exception exists -- `explicitWideLineWidthPx_`, set here,
// consulted only by `fl_xyline()`/`fl_yxline()`'s 3-arg forms (see
// their own doc comments) so a genuinely wide explicit pen
// (`lineStyle(lineSolid, N)`, `|N| > 1`) draws at its real requested
// thickness instead of those two functions' own hardcoded "always
// exactly 1 logical unit" default-hairline formula (see
// `test/unittest_fast_shapes`' "4"/"5" tabs' second
// sub-tests), without adding the general
// `line_width_` state this comment otherwise still correctly says
// isn't tracked. Callers are responsible for restoring lineSolid/width
// 0 themselves when done, exactly as FLTK's own fl_line_style()
// doc comment already requires ("it is your responsibility to set it
// back to the default").

/// Dash patterns for the PostScript driver, from `Fl_Graphics_Driver::
/// dashes_flat`/`dashes_cap`, indexed by the style's low byte (lineSolid,
/// lineDash, lineDot, lineDashDot, lineDashDotDot) and multiplied by the
/// line width. Round and square caps extend every dash at both ends, so
/// their dashes are shorter and their gaps wider than the flat ones.
package(fl) immutable int[][5] dashesFlat = [[], [3, 1], [1, 1], [3, 1, 1, 1], [3, 1, 1, 1, 1, 1]];
/// ditto, for round and square caps.
package(fl) immutable double[][5] dashesCap = [[], [2, 2], [0.01, 1.99], [2, 2, 0.01, 1.99],
    [2, 2, 0.01, 1.99, 0.01, 1.99]];

/**
 * Computes the auto dash/gap pattern for style's low byte (lineDash/
 * lineDot/lineDashDot/lineDashDotDot) at the given width (already
 * normalized to non-negative, nonzero by the caller) -- ported from the
 * dash-computing half of Fl_Xlib_Graphics_Driver::line_style_unscaled()
 * (the `if (!ndashes && (style&0xff))` branch, `style & 0x200`'s cap-
 * round length adjustment included). Returns an empty array for
 * lineSolid (style's low byte 0) -- lineStyle() only ever consults
 * this when the caller passed no explicit dashes of its own. Split out
 * as a pure function (no XSetDashes() call) so it's testable without a
 * live X display, unlike the rest of this section.
 *
 * Not ported: FLTK's `if (*dashes == 0) ndashes = 0` guard against a
 * zero-length first byte from extremely small *scaled* widths -- this
 * function itself doesn't consult `fl.core.screenScale(int)`, but its
 * caller `lineStyle()` does, and passes in an
 * already-scaled `width`, so the guard's real-world trigger (a `char`
 * dash/dot length wrapping to 0) is only reachable at scale factors
 * large enough to overflow a `ubyte` -- not exercised by anything in
 * this port yet.
 *
 * `package(fl)`, not `private`: `fl.svg_file_surface.SvgGraphicsDriver.
 * lineStyle()` reuses this directly rather than re-deriving FLTK's
 * own separate, SVG-specific dash-computing logic (`Fl_SVG_Graphics_
 * Driver::compute_dasharray()`) -- same auto-dash-from-style-bits
 * arithmetic either way, no reason to duplicate it.
 */
package(fl) ubyte[] dashPatternFor(int style, int width)
{
    int w = width ? width : 1;
    ubyte dash, dot, gap;
    if (style & capRound)
    {
        dash = cast(ubyte)(2 * w);
        dot = 1; // unfortunately 0 does not work (FLTK's own comment)
        gap = cast(ubyte)(2 * w - 1);
    }
    else
    {
        dash = cast(ubyte)(3 * w);
        dot = gap = cast(ubyte) w;
    }

    switch (style & 0xff)
    {
    case lineDash:       return [dash, gap];
    case lineDot:        return [dot, gap];
    case lineDashDot:    return [dash, gap, dot, gap];
    case lineDashDotDot: return [dash, gap, dot, gap, dot, gap];
    default:             return [];
    }
}

unittest
{
    // dashPatternFor(): pure arithmetic, no display needed.
    assert(dashPatternFor(lineSolid, 1) == []);
    assert(dashPatternFor(lineDash, 1) == [3, 1]);
    assert(dashPatternFor(lineDot, 1) == [1, 1]);
    assert(dashPatternFor(lineDashDot, 1) == [3, 1, 1, 1]);
    assert(dashPatternFor(lineDashDotDot, 1) == [3, 1, 1, 1, 1, 1]);

    // Width 2: dash=3*w, dot=gap=w for the non-round-cap branch.
    assert(dashPatternFor(lineDash, 2) == [6, 2]);
    assert(dashPatternFor(lineDot, 2) == [2, 2]);
    assert(dashPatternFor(lineDashDot, 2) == [6, 2, 2, 2]);

    // capRound adjusts lengths differently: dash=2*w, dot=1, gap=2*w-1.
    assert(dashPatternFor(lineDash | capRound, 2) == [4, 3]);
    assert(dashPatternFor(lineDot | capRound, 2) == [1, 3]);

    // width 0 normalizes to 1 inside dashPatternFor() itself (`width ?
    // width : 1`), matching FLTK's `int w = width ? width : 1;`.
    assert(dashPatternFor(lineDash, 0) == [3, 1]);
}

/**
 * Sets the line style (dash pattern), pen width, cap, and join used by
 * subsequent line/rect-outline drawing calls. Dispatches to
 * `fl.graphics_driver.currentDriver` first when one is active; otherwise
 * real on Linux, ported from Fl_Xlib_Graphics_Driver::
 * line_style_unscaled(), collapsed with `Fl_Scalable_Graphics_Driver::
 * line_style()`'s own scale-multiplication step: a 0 width stays X11's
 * "thin/cosmetic" 1-device-pixel default only below 2x scale, becoming
 * `int(currentScale())` at or above it (FLTK's own
 * `scale() < 2 ? 0 : scale()`); a nonzero width is `abs()`'d then
 * multiplied by `currentScale()`, matching `width>0 ? width*scale() :
 * -width*scale()` exactly.
 *
 * The scale multiplication matters: skipping it (`abs()` only, `int
 * lineWidth = width == 0 ? 0 : (width > 0 ? width :
 * -width);`) would leave every
 * `lineStyle()`-drawn line (`fl.grid`'s grid lines, `fl.symbols`'
 * arrow-shaft strokes, `fl.text_display`'s strikethrough/underline)
 * a constant on-screen thickness through a Ctrl-+/Ctrl-- rescale
 * while every other scaled primitive (`fl_rectf()`/`fl_xyline()`/box
 * borders) grows or shrinks proportionally, unlike real
 * FLTK, where `Fl::line_style()`-drawn lines do scale. `dashPatternFor()`
 * receives this already-scaled width (unchanged itself, see its own doc
 * comment).
 *
 * `dashes`, if given non-empty, is used as-is -- matching FLTK's
 * priority, an explicit dash array always wins over `style`'s low byte
 * even if that's lineSolid. Otherwise dashPatternFor() derives one from
 * `style`'s low byte and cap bits, or stays empty (solid) for lineSolid.
 */
void lineStyle(int style, int width = 0, const(ubyte)[] dashes = null)
{
    if (currentDriver !is null)
    {
        currentDriver.lineStyle(style, width, dashes);
        return;
    }
    version (linux)
    {
        if (gc_ is null) return;
        float s = currentScale();
        int lineWidth = width == 0
            ? (s < 2 ? 0 : cast(int) s)
            : cast(int)((width > 0 ? width : -width) * s);
        // See explicitWideLineWidthPx_'s own doc comment: fl_xyline()/
        // fl_yxline() need to know when a genuinely wide pen (not just
        // the default hairline, which can itself be >1 device pixel at
        // scale >= 2) is active. Zero -- not `lineWidth` -- for a
        // default-width call (`width == 0`) or an explicit width whose
        // magnitude is 1 (visually equivalent to the default at every
        // scale this port supports), so their existing default-hairline
        // formula stays exactly as it was for both those cases.
        int rawWidth = width < 0 ? -width : width;
        explicitWideLineWidthPx_ = rawWidth > 1 ? lineWidth : 0;

        const(ubyte)[] d = dashes;
        if (d.length == 0 && (style & 0xff) != 0)
            d = dashPatternFor(style, lineWidth);
        penNeedsXDrawLine_ = d.length != 0 || ((style >> 8) & 3) >= 2;
        penCustom_ = style != 0 || width != 0 || dashes.length != 0;

        static immutable int[4] capTable = [CapButt, CapButt, CapRound, CapProjecting];
        static immutable int[4] joinTable = [JoinMiter, JoinMiter, JoinRound, JoinBevel];
        XSetLineAttributes(display_, gc_, cast(uint) lineWidth,
            d.length ? LineOnOffDash : LineSolid,
            capTable[(style >> 8) & 3], joinTable[(style >> 12) & 3]);
        if (d.length) XSetDashes(display_, gc_, 0, d.ptr, cast(int) d.length);
    }
}

/**
 * Sets/gets the "antialias" hint (`Fl_Graphics_Driver::antialias(int)`/
 * `antialias()`, `FL/fl_draw.H`'s inline `fl_antialias()`). Forwards to
 * `fl.graphics_driver.currentDriver` when one is active, matching
 * FLTK's own inline `fl_antialias()`/`fl_can_do_alpha_blending()`-
 * style dispatch through `fl_graphics_driver` exactly -- a genuine
 * no-op pair (hardcoded `0`/ignored) only when no driver is active, or
 * on a driver that hasn't overridden `GraphicsDriver.antialias()`'s own
 * non-abstract no-op default (this port's Xlib backend has no override,
 * faithfully matching FLTK's base `Fl_Graphics_Driver::antialias()`
 * letter for letter -- only Windows' `GdiPlusGraphicsDriver`, this
 * port's first real override, makes this do anything observable).
 * Exists so callers like `fl.text_display`'s underline/strikethrough
 * drawing (which brackets its line-drawing with `fl_antialias(1)`/
 * restore, matching FLTK's own `Fl_Text_Display::draw_string()`)
 * have something real to call.
 */
int antialias() { return currentDriver !is null ? currentDriver.antialias() : 0; }
void antialias(int state) { if (currentDriver !is null) currentDriver.antialias(state); }

/**
 * Draws a dotted-line rectangle outline inside (x,y,w,h) in the current
 * fl_color() -- the keyboard-focus indicator every interactive widget's
 * drawFocus() draws. Ported from Fl_Xlib_Graphics_Driver::focus_rect()
 * (the Xlib-specific override, not the generic Fl_Graphics_Driver base
 * class's plain `line_style(FL_DOT); rect(...); line_style(FL_SOLID);`
 * -- the Xlib override additionally preserves/restores the driver's
 * current line width and forces width 1 for the dashed draw itself when
 * that saved width was 0, see the bug-fix note below for why that
 * distinction is load-bearing). Now built on the real, general
 * lineStyle() above rather than hand-inlined XSetLineAttributes()/
 * XSetDashes() calls -- no version(linux) split needed any more
 * (lineStyle()/fl_rect() already have their own).
 *
 * DELIBERATE SIMPLIFICATION, matching lineStyle()'s own: no
 * persistent line-width state exists to save/restore the way FLTK's
 * `int lw_save = line_width_; ...; if (lw_save==0) line_style(FL_SOLID,
 * 0); else line_style(FL_SOLID);` does. Every caller in this port that
 * ever changes the line width (fl.grid's drawGrid(), the only one so
 * far) already restores width 0 itself before anything else draws, per
 * lineStyle()'s own documented contract -- so `lw_save` is always 0
 * in practice here, and this hardcodes exactly that case rather than
 * tracking state nothing else needs yet. Revisit if a future caller
 * ever draws a focus rect from inside its own temporarily-widened
 * line_style() block.
 *
 * Line width must be 1, not 0: the real Xlib override
 * doesn't use width 0 for the dashed draw itself; it
 * explicitly checks `if (line_width_ == 0) line_style(FL_DOT, 1); else
 * line_style(FL_DOT);`, i.e. it forces a real width-1 line whenever the
 * driver's current width happens to be the 0 default, specifically for
 * this call. That distinction is load-bearing, not
 * cosmetic: width-0 ("thin") lines are drawn via a different, faster
 * server-side path than width>=1 ("wide") lines, and the X11 spec
 * leaves dash-pattern rendering for that fast path under-specified --
 * without the width-1 force, a
 * `ShortcutButton`'s focus rectangle can show a stretch of solid black
 * instead of fine dots partway along one edge (see
 * `smoke-tests/shortcut_button.d`'s "Action"
 * button's dashed top edge for a visual check). `lineStyle(lineDot, 1)` below
 * reproduces that width-1 call exactly (same width, same
 * LineOnOffDash/CapButt/JoinMiter, same `[1,1]` dash bytes as the
 * hardcoded calls this replaced).
 */
void focusRect(int x, int y, int w, int h)
{
    lineStyle(lineDot, 1);
    fl_rect(x, y, w, h);
    lineStyle(lineSolid, 0);
}

// ---------------------------------------------------------------------
// Shadow/engraved/embossed label drawing (src/fl_engraved_label.cxx)
// ---------------------------------------------------------------------
//
// Backs Labeltype.shadowLabel/engravedLabel/embossedLabel (fl.widget's
// Label.draw()). FLTK reaches these via Fl::set_labeltype(), only
// ever triggered by referencing the FL_SHADOW_LABEL/FL_ENGRAVED_LABEL/
// FL_EMBOSSED_LABEL constants themselves -- each is a macro
// (`#define FL_SHADOW_LABEL fl_define_FL_SHADOW_LABEL()`, FL/
// Enumerations.H) that calls a registration function as a side effect
// of merely being referenced, so any program naming these constants at
// all (as every real caller must, to use them) gets the real pixel
// effect out of the box, with no separate opt-in step. This port's
// Label.draw() has no such registration table (see that function's own
// doc comment on the deliberate simplification for normalLabel) -- it
// dispatches directly, so these three are called directly too, from
// its shadowLabel/engravedLabel/embossedLabel cases, each wrapped in a
// small delegate literal to satisfy fl_draw()'s DrawTextCb (see that
// alias's own doc comment for why a free function can't be passed
// directly -- a D delegate carries a context pointer a plain function
// pointer doesn't).

/// Draws str n times at (x+dx,y+dy) for each (dx,dy,color) triple in
/// data, in the paired color -- except the last entry, which draws in
/// whatever color was active when this was called (the label's own
/// real color), restored afterward. Ported from the `innards()` helper
/// shared by shadowLabelDraw()/engravedLabelDraw()/
/// fl_embossed_label_draw() below (src/fl_engraved_label.cxx).
private void labelInnards(const(char)[] str, int n, int x, int y, const(int[3])[] data)
{
    Color c = fl_color();
    foreach (i, d; data)
    {
        fl_color(i < data.length - 1 ? cast(Color) d[2] : c);
        fl_draw(str, n, x + d[0], y + d[1]);
    }
    fl_color(c);
}

/// Draw callback for Labeltype.shadowLabel: the text plus a dark3 drop
/// shadow offset (2,2). Ported from fl_shadow_label_draw().
void shadowLabelDraw(const(char)[] str, int n, int x, int y)
{
    static immutable int[3][2] data = [[2, 2, dark3], [0, 0, 0]];
    labelInnards(str, n, x, y, data);
}

/// Draw callback for Labeltype.engravedLabel: a light3/dark3 bevel
/// that reads as pressed into the surface. Ported from
/// engravedLabelDraw().
void engravedLabelDraw(const(char)[] str, int n, int x, int y)
{
    static immutable int[3][7] data = [
        [1, 0, light3], [1, 1, light3], [0, 1, light3],
        [-1, 0, dark3], [-1, -1, dark3], [0, -1, dark3],
        [0, 0, 0]
    ];
    labelInnards(str, n, x, y, data);
}

/// Draw callback for Labeltype.embossedLabel: the mirror image of
/// engravedLabelDraw() -- reads as raised off the surface. Ported
/// from embossedLabelDraw().
void embossedLabelDraw(const(char)[] str, int n, int x, int y)
{
    static immutable int[3][7] data = [
        [-1, 0, light3], [-1, -1, light3], [0, -1, light3],
        [1, 0, dark3], [1, 1, dark3], [0, 1, dark3],
        [0, 0, 0]
    ];
    labelInnards(str, n, x, y, data);
}

/// Ported from fl_rounded_box.cxx's fl_rounded_focus() -- the shaped
/// focus ring for the "rounded" boxtype family (roundedBox/rshadowBox/
/// roundedFrame/rflatBox), reusing the same roundedRectClamped() radius
/// math those boxtypes' own fills/outlines already use.
private void flRoundedFocus(Boxtype bt, int x, int y, int w, int h, Color fg, Color bg)
{
    x += fl.core.boxDx(bt);
    y += fl.core.boxDy(bt);
    w -= fl.core.boxDw(bt) + 1;
    h -= fl.core.boxDh(bt) + 1;
    Color saved = fl_color();
    fl_color(contrast(fg, bg));
    lineStyle(lineDot);
    roundedRectClamped(false, x + 1, y + 1, w - 1, h - 1);
    lineStyle(lineSolid);
    fl_color(saved);
}

/// Ported from fl_round_box.cxx's fl_round_focus() -- the shaped focus
/// ring for round-button boxtypes (roundUpBox/roundDownBox and their
/// plastic/gtk+/oxy scheme variants), reusing roundBoxPart()'s outline
/// (`roundClosed`) arc construction.
private void flRoundFocus(Boxtype bt, int x, int y, int w, int h, Color fg, Color bg)
{
    x += fl.core.boxDx(bt);
    y += fl.core.boxDy(bt);
    w -= fl.core.boxDw(bt);
    h -= fl.core.boxDh(bt);
    Color saved = fl_color();
    lineStyle(lineDot);
    roundBoxPart(roundClosed, x, y, w, h, 0, contrast(fg, bg));
    lineStyle(lineSolid);
    fl_color(saved);
}

/// Ported from fl_diamond_box.cxx's fl_diamond_focus() -- a dotted
/// diamond outline for diamondUpBox/diamondDownBox.
private void flDiamondFocus(Boxtype bt, int x, int y, int w, int h, Color fg, Color bg)
{
    w &= ~1;
    h &= ~1;
    x += fl.core.boxDx(bt) + 4;
    y += fl.core.boxDy(bt) + 4;
    w -= fl.core.boxDw(bt) + 8;
    h -= fl.core.boxDh(bt) + 8;
    int x1 = x + w / 2;
    int y1 = y + h / 2;
    Color saved = fl_color();
    fl_color(contrast(fg, bg));
    lineStyle(lineDot);
    loop(x, y1, x1, y, x + w, y1, x1, y + h);
    lineStyle(lineSolid);
    fl_color(saved);
}

/// Ported from fl_oval_box.cxx's fl_oval_focus() -- a dotted ellipse
/// for ovalBox/oshadowBox/ovalFrame/oflatBox.
private void flOvalFocus(Boxtype bt, int x, int y, int w, int h, Color fg, Color bg)
{
    x += fl.core.boxDx(bt) + 1;
    y += fl.core.boxDy(bt) + 1;
    w -= fl.core.boxDw(bt) + 2;
    h -= fl.core.boxDh(bt) + 2;
    Color saved = fl_color();
    fl_color(contrast(fg, bg));
    lineStyle(lineDot);
    fl_arc(x, y, w, h, 0, 360);
    lineStyle(lineSolid);
    fl_color(saved);
}

/**
 * Draws a widget's keyboard-focus indicator inside (x,y,w,h) -- a
 * dotted rectangle in a color contrasting against `bg`, inset by the
 * boxtype's own margins (and nudged +1,+1 for a down-style box, so the
 * dots don't sit under the bevel). Ported from fl_draw_box_focus()
 * (src/fl_boxtype.cxx). No-op if Fl::visible_focus() is off.
 *
 * FLTK's `fl_box_table[bt].ff` per-boxtype focus-drawing dispatch
 * -- round/oval/diamond/rounded boxtypes get a matching-shaped focus
 * ring instead of a rectangular one -- is real.
 * The round/oval/diamond/rounded-family shaped functions
 * (`flRoundFocus()`/`flOvalFocus()`/`flDiamondFocus()`/
 * `flRoundedFocus()` just above) are checked first, exactly matching
 * FLTK's dispatch order and each shape's own dx/dy/dw/dh math (no
 * shared pre-adjustment -- every shaped function does its own, same as
 * FLTK); every other boxtype still falls through to the generic
 * rectangular outline below.
 */
void drawBoxFocus(Boxtype bt, int x, int y, int w, int h, Color fg, Color bg)
{
    if (!fl.core.visibleFocus()) return;

    switch (bt)
    {
    case Boxtype.roundedBox:
    case Boxtype.rshadowBox:
    case Boxtype.roundedFrame:
    case Boxtype.rflatBox:
        flRoundedFocus(bt, x, y, w, h, fg, bg);
        return;
    case Boxtype.roundUpBox:
    case Boxtype.roundDownBox:
    case Boxtype.plasticRoundUpBox:
    case Boxtype.plasticRoundDownBox:
    case Boxtype.gtkRoundUpBox:
    case Boxtype.gtkRoundDownBox:
    case Boxtype.oxyRoundUpBox:
    case Boxtype.oxyRoundDownBox:
        flRoundFocus(bt, x, y, w, h, fg, bg);
        return;
    case Boxtype.diamondUpBox:
    case Boxtype.diamondDownBox:
        flDiamondFocus(bt, x, y, w, h, fg, bg);
        return;
    case Boxtype.ovalBox:
    case Boxtype.oshadowBox:
    case Boxtype.ovalFrame:
    case Boxtype.oflatBox:
        flOvalFocus(bt, x, y, w, h, fg, bg);
        return;
    default:
        break;
    }

    switch (bt)
    {
    case Boxtype.downBox:
    case Boxtype.downFrame:
    case Boxtype.thinDownBox:
    case Boxtype.thinDownFrame:
        x++;
        y++;
        break;
    default:
        break;
    }
    x += fl.core.boxDx(bt);
    y += fl.core.boxDy(bt);
    w -= fl.core.boxDw(bt) + 1;
    h -= fl.core.boxDh(bt) + 1;

    Color saved = fl_color();
    fl_color(contrast(fg, bg));
    focusRect(x, y, w, h);
    fl_color(saved);
}

// ---------------------------------------------------------------------
// Box drawing (src/fl_boxtype.cxx)
// ---------------------------------------------------------------------
//
// Ported from the box-drawing half of fl_boxtype.cxx (the metrics half
// -- dx/dy/dw/dh insets -- already lives in fl.core.boxTable). Covers
// noBox/flatBox/upBox/downBox/upFrame/downFrame/thinUpBox/thinDownBox/
// thinUpFrame/thinDownFrame/engravedBox/engravedFrame/embossedBox/
// embossedFrame/borderBox/borderFrame/shadowBox/shadowFrame here, plus
// the round/oval/diamond family (see the section comment further down
// this module) and the "rounded" CSS-style family (see the section
// comment above roundedRectLut) elsewhere in this file. All four
// plastic/gtk+/gleam/oxy scheme families are
// real too, each in its own section further down this module (see
// gtkColor()/gleamColor()/oxyColor()/shadeColor()'s own section
// comments) and wired into drawBoxAt()'s switch below. Every boxtype
// fl.core.boxTable has metrics for is drawable; drawBoxAt()'s
// default: case is pure forward-compat, not a real gap.

/// Ported from FLTK's `draw_it_active` (`fl_boxtype.cxx`, a
/// process-wide flag `Fl_Widget::draw_box()` sets around its own call
/// into `fl_box_table[t].f`) -- whether the box/frame currently being
/// drawn should use its normal or dimmed gray-ramp shades. Defaults to
/// `true` (matching FLTK's own `static int draw_it_active = 1;`
/// initializer), so any *direct* `drawBoxAt()` caller that never
/// touches this (custom-drawn widgets, matching FLTK's own public
/// `fl_draw_box()` free function, which also never sets the flag)
/// keeps drawing at full brightness by default -- only `Widget.
/// drawBox()` (mirroring `Fl_Widget::draw_box()`) sets it low around
/// its own call.
private bool drawItActive_ = true;

/// Setter half of `drawItActive_` -- `package(fl)` since only
/// `Widget.drawBox()` should ever need to flip this (see that
/// function's own doc comment for why: it's the direct equivalent of
/// FLTK's `Fl_Widget::draw_box()` setting `draw_it_active` around
/// its own dispatch into the box table).
package(fl) void drawBoxActive(bool v) { drawItActive_ = v; }

/// Button bevels/outlines
/// and slider "decorations" -- the thin-down-box bevel drawn around a
/// slider's thumb/ticks -- need to dim too, not just box *fills*: FLTK's
/// `fl_gray_ramp()` (`fl_boxtype.cxx`) doesn't compute a dimmed shade
/// on demand the way `inactive()` does for an arbitrary color --
/// it swaps between two entirely separate, pre-baked 24-entry lookup
/// tables (`active_ramp`/`inactive_ramp`) based on `draw_it_active`,
/// and `inactive_ramp`'s values are literal hardcoded palette indices
/// (43-52), not `colorAverage()`-derived. `flFrame2()`/`flUpFrame()`/
/// `flDownFrame()`/etc. (the beveled-border half of every classic
/// up/down boxtype, called from `drawBoxAt()`, entirely separate from
/// the flat fill color a caller passes in) all route through this, so
/// they need this same table swap, not just a dimmed fill color, to
/// match FLTK's real inactive look.
private static immutable ubyte[24] inactiveGrayRampIndex = [
    43, 43, 44, 44, 44, 45, 45, 46, 46, 46, 47, 47,
    48, 48, 48, 49, 49, 49, 50, 50, 51, 51, 52, 52,
];

/// FLTK's `fl_gray_ramp()` (no-arg overload used inside fl_frame()/
/// fl_frame2(), distinct from the int-taking Fl::gray_ramp()-style
/// overload) maps a letter 'A'..'X' to a shade of gray, darkest to
/// lightest -- i.e. fl.enumerations.colorTable[gray0 .. gray0+23] when
/// `drawItActive_`, or the separate `inactiveGrayRampIndex` table
/// (literal palette indices, matching FLTK's own `inactive_ramp`)
/// otherwise.
private Color grayRampChar(char c)
{
    int idx = c - 'A';
    return drawItActive_ ? cast(Color)(gray0 + idx) : cast(Color) inactiveGrayRampIndex[idx];
}

/**
 * Draws a beveled frame by walking groups of 4 grayscale line
 * segments (bottom, right, top, left), closing inward by one pixel
 * each group -- ported verbatim from fl_frame2() (fl_boxtype.cxx). s
 * must be a multiple of 4 characters ('A'..'X'); behavior is undefined
 * otherwise, matching FLTK's own documented caveat.
 */
private void flFrame2(string s, int x, int y, int w, int h)
{
    if (h <= 0 || w <= 0) return;

    size_t i = 0;
    while (i < s.length)
    {
        fl_color(grayRampChar(s[i++]));
        fl_xyline(x, y + h - 1, x + w - 1);
        if (--h <= 0) break;

        fl_color(grayRampChar(s[i++]));
        fl_yxline(x + w - 1, y + h - 1, y);
        if (--w <= 0) break;

        fl_color(grayRampChar(s[i++]));
        fl_xyline(x, y, x + w - 1);
        y++;
        if (--h <= 0) break;

        fl_color(grayRampChar(s[i++]));
        fl_yxline(x, y + h - 1, y);
        x++;
        if (--w <= 0) break;
    }
}

/// Ported from fl_up_frame() (fl_boxtype.cxx), the BORDER_WIDTH==2
/// (this port's only supported border width, see fl.core's boxTable
/// note on D1/D2) case.
private void flUpFrame(int x, int y, int w, int h)
{
    flFrame2("AAWWMMTT", x, y, w, h);
}

/// Ported from fl_up_box().
private void flUpBox(int x, int y, int w, int h, Color c)
{
    flUpFrame(x, y, w, h);
    fl_color(c);
    fl_rectf(x + 2, y + 2, w - 4, h - 4);
}

/// Ported from fl_down_frame(), BORDER_WIDTH==2 case.
private void flDownFrame(int x, int y, int w, int h)
{
    flFrame2("WWMMPPAA", x, y, w, h);
}

/// Ported from fl_down_box().
private void flDownBox(int x, int y, int w, int h, Color c)
{
    flDownFrame(x, y, w, h);
    fl_color(c);
    fl_rectf(x + 2, y + 2, w - 4, h - 4);
}

/**
 * Same as flFrame2() but walks the 4-character groups in top, left,
 * bottom, right order instead of bottom, right, top, left -- ported
 * verbatim from fl_frame() (fl_boxtype.cxx; FLTK's own doc comment:
 * "The only difference between this function and fl_frame2() is the
 * order of the line segments").
 */
private void flFrame(string s, int x, int y, int w, int h)
{
    if (h <= 0 || w <= 0) return;

    size_t i = 0;
    while (i < s.length)
    {
        fl_color(grayRampChar(s[i++]));
        fl_xyline(x, y, x + w - 1);
        y++;
        if (--h <= 0) break;

        fl_color(grayRampChar(s[i++]));
        fl_yxline(x, y + h - 1, y);
        x++;
        if (--w <= 0) break;

        fl_color(grayRampChar(s[i++]));
        fl_xyline(x, y + h - 1, x + w - 1);
        if (--h <= 0) break;

        fl_color(grayRampChar(s[i++]));
        fl_yxline(x + w - 1, y + h - 1, y);
        if (--w <= 0) break;
    }
}

/// Ported from fl_thin_down_frame() -- the BORDER_WIDTH==1 sibling of
/// flDownFrame()'s BORDER_WIDTH==2.
private void flThinDownFrame(int x, int y, int w, int h)
{
    flFrame2("WWHH", x, y, w, h);
}

/// Ported from fl_thin_down_box().
private void flThinDownBox(int x, int y, int w, int h, Color c)
{
    flThinDownFrame(x, y, w, h);
    fl_color(c);
    fl_rectf(x + 1, y + 1, w - 2, h - 2);
}

/// Ported from fl_thin_up_frame() -- the BORDER_WIDTH==1 sibling of
/// flUpFrame()'s BORDER_WIDTH==2.
private void flThinUpFrame(int x, int y, int w, int h)
{
    flFrame2("HHWW", x, y, w, h);
}

/// Ported from fl_thin_up_box().
private void flThinUpBox(int x, int y, int w, int h, Color c)
{
    flThinUpFrame(x, y, w, h);
    fl_color(c);
    fl_rectf(x + 1, y + 1, w - 2, h - 2);
}

/// Ported from fl_engraved_frame().
private void flEngravedFrame(int x, int y, int w, int h)
{
    flFrame("HHWWWWHH", x, y, w, h);
}

/// Ported from fl_engraved_box().
private void flEngravedBox(int x, int y, int w, int h, Color c)
{
    flEngravedFrame(x, y, w, h);
    fl_color(c);
    fl_rectf(x + 2, y + 2, w - 4, h - 4);
}

/// Ported from fl_embossed_frame().
private void flEmbossedFrame(int x, int y, int w, int h)
{
    flFrame("WWHHHHWW", x, y, w, h);
}

/// Ported from fl_embossed_box().
private void flEmbossedBox(int x, int y, int w, int h, Color c)
{
    flEmbossedFrame(x, y, w, h);
    fl_color(c);
    fl_rectf(x + 2, y + 2, w - 4, h - 4);
}

/// Ported from fl_border_frame().
private void flBorderFrame(int x, int y, int w, int h, Color c)
{
    fl_rect(x, y, w, h, c);
}

/// Draws a filled rectangle in color c with a black outline. Backs
/// borderBox (`#define fl_border_box fl_rectbound` FLTK -- same
/// function, just aliased under the boxtype's own name there); also a
/// public standalone drawing primitive in its own right FLTK, now
/// that fl.chart's draw_barchart()/draw_horbarchart() call it that way
/// directly.
void rectbound(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    fl_rectf(x, y, w, h);
    fl_rect(x, y, w, h, black);
}

/// Ported from fl_shadow_frame(). Draws a drop shadow (boxShadowWidth()
/// pixels, dark3-colored) below and to the right of a plain c-colored
/// bordered rect.
private void flShadowFrame(int x, int y, int w, int h, Color c)
{
    int bw = fl.core.boxShadowWidth();
    fl_color(dark3);
    fl_rectf(x + bw, y + h - bw, w - bw, bw);
    fl_rectf(x + w - bw, y + bw, bw, h - bw);
    fl_rect(x, y, w - bw, h - bw, c);
}

/// Ported from fl_shadow_box().
private void flShadowBox(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    fl_rectf(x, y, w - fl.core.boxShadowWidth(), h - fl.core.boxShadowWidth());
    flShadowFrame(x, y, w, h, gray0);
}

// ---------------------------------------------------------------------
// Oval/round/diamond box families (src/fl_oval_box.cxx/
// src/fl_round_box.cxx/src/fl_diamond_box.cxx)
// ---------------------------------------------------------------------
//
// Ported now that fl_pie()/fl_arc() are real (see the ellipse/pie
// section above) -- these three families draw almost entirely with
// primitives already real in this module (fl_pie/fl_arc/fl_rectf/
// fl_polygon/fl_yxline (3-arg)/fl_xyline (3-arg)), plus the new 3-point
// fl_line()/4-point loop() overloads just above (needed only by the
// diamond family's bevel lines). DELIBERATE SIMPLIFICATION shared by
// all three: FLTK calls `Fl::box_color(c)`/`Fl::set_box_color(c)`
// (`fl_color(active_r() ? c : inactive(c))`, tracked via a
// process-wide `draw_it_active` flag box-drawing code sets before
// calling into the table) rather than `fl_color(c)` directly; this port
// never ported that flag -- as documented where drawBoxAt() itself is
// defined, every boxtype function here just draws with whatever Color
// its caller passed, and active/inactive dimming is the *caller's*
// responsibility (e.g. fl.dial's `activeR() ? color() :
// inactive(color())` before drawing) -- so `Fl::box_color(c)` here
// collapses to plain `fl_color(c)`, exactly like every other boxtype
// function in this module already does. The "rounded" (CSS-style,
// configurable corner radius) family (roundedBox/rshadowBox/
// roundedFrame/rflatBox) is ported too -- see the section comment above roundedRect() further
// down this module for that family's own writeup.

/// Ported from fl_oval_box.cxx's fl_oval_flat_box().
private void flOvalFlatBox(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    fl_pie(x, y, w, h, 0, 360);
}

/// Ported from fl_oval_box.cxx's fl_oval_frame().
private void flOvalFrame(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    fl_arc(x, y, w, h, 0, 360);
}

/// Ported from fl_oval_box.cxx's fl_oval_box().
private void flOvalBox(int x, int y, int w, int h, Color c)
{
    flOvalFlatBox(x, y, w, h, c);
    flOvalFrame(x, y, w, h, black);
}

/// Ported from fl_oval_box.cxx's fl_oval_shadow_box().
private void flOvalShadowBox(int x, int y, int w, int h, Color c)
{
    int bw = fl.core.boxShadowWidth();
    flOvalFlatBox(x + bw, y + bw, w, h, dark3);
    flOvalBox(x, y, w, h, c);
}

/// Which arc/pie fragment roundBoxPart() draws -- ported from
/// fl_round_box.cxx's anonymous `{UPPER_LEFT, LOWER_RIGHT, CLOSED,
/// FILL}` enum.
private enum : int { roundUpperLeft, roundLowerRight, roundClosed, roundFill }

/// Signature shared by fl_pie()/fl_arc() -- lets roundBoxPart() below
/// pick one or the other via a function pointer, matching FLTK's
/// own `void (*f)(int,int,int,int,double,double)` (FLTK's own
/// comment there notes this exists only to dodge an unrelated compiler
/// bug with taking `&fl_arc`'s address directly under one particular
/// vendor's compiler -- not applicable to dmd/ldc/gdc, but the function-
/// pointer indirection itself is still the simplest way to share the
/// rest of this function's geometry between the outline and fill
/// cases).
private alias ArcFn = void function(int, int, int, int, double, double);

/**
 * Draws one fragment (which: roundUpperLeft/roundLowerRight/
 * roundClosed/roundFill) of a round box's outline or fill, inset by
 * inset pixels, in color. Ported verbatim from fl_round_box.cxx's
 * anonymous `draw()` -- backs both flRoundUpBox()/flRoundDownBox()
 * (called several times each, at different insets/colors, to build up
 * the beveled-circle look from concentric gray-ramp arcs) via repeated
 * calls, exactly as FLTK's fl_round_up_box()/fl_round_down_box() do.
 */
private void roundBoxPart(int which, int x, int y, int w, int h, int inset, Color color)
{
    if (inset * 2 >= w) inset = (w - 1) / 2;
    if (inset * 2 >= h) inset = (h - 1) / 2;
    x += inset;
    y += inset;
    w -= 2 * inset;
    h -= 2 * inset;
    int d = w <= h ? w : h;
    if (d <= 1) return;
    fl_color(color);
    ArcFn f = (which == roundFill) ? &fl_pie : &fl_arc;
    if (which >= roundClosed)
    {
        if (w == h) f(x, y, d, d, 0, 360);
        else
        {
            f(x + w - d, y, d, d, w <= h ? 0 : -90, w <= h ? 180 : 90);
            f(x, y + h - d, d, d, w <= h ? 180 : 90, w <= h ? 360 : 270);
        }
    }
    else if (which == roundUpperLeft)
    {
        if (w == h) f(x, y, d, d, 45, 225);
        else
        {
            f(x + w - d, y, d, d, 45, w <= h ? 180 : 90);
            f(x, y + h - d, d, d, w <= h ? 180 : 90, 225);
        }
    }
    else // roundLowerRight
    {
        if (w == h) f(x, y, d, d, 225, 405);
        else
        {
            f(x, y + h - d, d, d, 225, w <= h ? 360 : 270);
            f(x + w - d, y, d, d, w <= h ? 360 : 270, 360 + 45);
        }
    }
    if (which == roundFill)
    {
        if (w < h) fl_rectf(x, y + d / 2, w, h - (d & -2) + 1);
        else if (w > h) fl_rectf(x + d / 2, y, w - (d & -2) + 1, h);
    }
    else
    {
        if (w < h)
        {
            if (which != roundUpperLeft) fl_yxline(x + w - 1, y + d / 2 - 1, y + h - d / 2 + 1);
            if (which != roundLowerRight) fl_yxline(x, y + d / 2 - 1, y + h - d / 2 + 1);
        }
        else if (w > h)
        {
            if (which != roundUpperLeft) fl_xyline(x + d / 2 - 1, y + h - 1, x + w - d / 2 + 1);
            if (which != roundLowerRight) fl_xyline(x + d / 2 - 1, y, x + w - d / 2 + 1);
        }
    }
}

/// Ported from fl_round_box.cxx's fl_round_down_box().
private void flRoundDownBox(int x, int y, int w, int h, Color bgcolor)
{
    roundBoxPart(roundFill,       x,     y, w,     h, 2, bgcolor);
    roundBoxPart(roundUpperLeft,  x + 1, y, w - 2, h, 0, grayRampChar('N'));
    roundBoxPart(roundUpperLeft,  x + 1, y, w - 2, h, 1, grayRampChar('H'));
    roundBoxPart(roundUpperLeft,  x,     y, w,     h, 0, grayRampChar('N'));
    roundBoxPart(roundUpperLeft,  x,     y, w,     h, 1, grayRampChar('H'));
    roundBoxPart(roundLowerRight, x,     y, w,     h, 0, grayRampChar('S'));
    roundBoxPart(roundLowerRight, x + 1, y, w - 2, h, 0, grayRampChar('U'));
    roundBoxPart(roundLowerRight, x,     y, w,     h, 1, grayRampChar('U'));
    roundBoxPart(roundLowerRight, x + 1, y, w - 2, h, 1, grayRampChar('W'));
    roundBoxPart(roundClosed,     x,     y, w,     h, 2, grayRampChar('A'));
}

/// Ported from fl_round_box.cxx's fl_round_up_box().
private void flRoundUpBox(int x, int y, int w, int h, Color bgcolor)
{
    roundBoxPart(roundFill,       x,     y, w,     h, 2, bgcolor);
    roundBoxPart(roundLowerRight, x + 1, y, w - 2, h, 0, grayRampChar('H'));
    roundBoxPart(roundLowerRight, x + 1, y, w - 2, h, 1, grayRampChar('N'));
    roundBoxPart(roundLowerRight, x,     y, w,     h, 1, grayRampChar('H'));
    roundBoxPart(roundLowerRight, x,     y, w,     h, 2, grayRampChar('N'));
    roundBoxPart(roundUpperLeft,  x,     y, w,     h, 2, grayRampChar('U'));
    roundBoxPart(roundUpperLeft,  x + 1, y, w - 2, h, 1, grayRampChar('S'));
    roundBoxPart(roundUpperLeft,  x,     y, w,     h, 1, grayRampChar('W'));
    roundBoxPart(roundUpperLeft,  x + 1, y, w - 2, h, 0, grayRampChar('U'));
    roundBoxPart(roundClosed,     x,     y, w,     h, 0, grayRampChar('A'));
}

/// Ported from fl_diamond_box.cxx's fl_diamond_up_box(). FLTK's own
/// comment notes "the diamond box draws best if the area is square" --
/// `w &= -2`/`h &= -2` (round down to even) is FLTK's, not this
/// port's, and is kept as-is since the bevel-line geometry below
/// genuinely depends on w/h being even (it bisects them via `/2`).
private void flDiamondUpBox(int x, int y, int w, int h, Color bgcolor)
{
    w &= -2;
    h &= -2;
    int x1 = x + w / 2;
    int y1 = y + h / 2;
    fl_color(bgcolor);
    fl_polygon(x + 3, y1, x1, y + 3, x + w - 3, y1, x1, y + h - 3);
    fl_color(grayRampChar('W')); fl_line(x + 1, y1, x1, y + 1, x + w - 1, y1);
    fl_color(grayRampChar('U')); fl_line(x + 2, y1, x1, y + 2, x + w - 2, y1);
    fl_color(grayRampChar('S')); fl_line(x + 3, y1, x1, y + 3, x + w - 3, y1);
    fl_color(grayRampChar('P')); fl_line(x + 3, y1, x1, y + h - 3, x + w - 3, y1);
    fl_color(grayRampChar('N')); fl_line(x + 2, y1, x1, y + h - 2, x + w - 2, y1);
    fl_color(grayRampChar('H')); fl_line(x + 1, y1, x1, y + h - 1, x + w - 1, y1);
    fl_color(grayRampChar('A')); loop(x, y1, x1, y, x + w, y1, x1, y + h);
}

/// Ported from fl_diamond_box.cxx's fl_diamond_down_box().
private void flDiamondDownBox(int x, int y, int w, int h, Color bgcolor)
{
    w &= -2;
    h &= -2;
    int x1 = x + w / 2;
    int y1 = y + h / 2;
    fl_color(grayRampChar('P')); fl_line(x + 0, y1, x1, y + 0, x + w - 0, y1);
    fl_color(grayRampChar('N')); fl_line(x + 1, y1, x1, y + 1, x + w - 1, y1);
    fl_color(grayRampChar('H')); fl_line(x + 2, y1, x1, y + 2, x + w - 2, y1);
    fl_color(grayRampChar('W')); fl_line(x + 2, y1, x1, y + h - 2, x + w - 2, y1);
    fl_color(grayRampChar('U')); fl_line(x + 1, y1, x1, y + h - 1, x + w - 1, y1);
    fl_color(grayRampChar('S')); fl_line(x + 0, y1, x1, y + h - 0, x + w - 0, y1);
    fl_color(bgcolor);
    fl_polygon(x + 3, y1, x1, y + 3, x + w - 3, y1, x1, y + h - 3);
    fl_color(grayRampChar('A')); loop(x + 3, y1, x1, y + 3, x + w - 3, y1, x1, y + h - 3);
}

// ---------------------------------------------------------------------
// "Rounded" (CSS-style) box family (src/fl_rounded_box.cxx +
// Fl_Graphics_Driver::rounded_rect()/rounded_rectf() in
// src/Fl_Graphics_Driver.cxx)
// ---------------------------------------------------------------------
//
// Straight edges with a *rounded corner*
// (unlike the "round"/oval family above, which is fully round-sided),
// so drawn as a 20-point path (5 points per corner, a fixed lookup-table
// approximation of a quarter circle) via this module's existing
// transform-stack vertex path (beginPolygon()/beginLoop()/
// endPolygon()/endLoop()) rather than a new from-scratch
// primitive.
//
// DELIBERATE DEVIATION from vertex(): the 20 corner points are added
// via transformedVertex() (raw device coordinates), not vertex()
// (which would additionally apply the current transform matrix) --
// matching FLTK's own `Fl_Graphics_Driver::_rbox()`, which calls
// `transformed_vertex()`, not `vertex()`, for exactly this reason: box
// drawing is always axis-aligned in device space, with no dependency on
// (and no interaction expected with) fl.dial's/fl.clock's rotate/scale
// transform stack.

private static immutable double[5] roundedRectLut = [0.0, 0.07612, 0.29289, 0.61732, 1.0];

/**
 * Draws (filled if `fill`, else outlined) a rectangle inscribed in
 * (x,y,w,h) with corner radius r -- the shared geometry behind
 * roundedRect()/roundedRectf() below. Ported verbatim from
 * Fl_Graphics_Driver::_rbox() (including its `r==5 -> 4`/`r==7 -> 8`
 * corner-size snapping -- FLTK's own comments: "use only even
 * sizes for small corners (STR #2943)" and "note: 8 is better than 6
 * (really)" -- and the 5-point-per-corner lookup table, a fixed
 * approximation of a quarter circle).
 *
 * Like every beginPolygon()/beginLoop()/beginPoints()/
 * beginLine()/beginComplexPolygon() path, this owns the single
 * shared vertexPoints_/vertexKind_ buffer for its own begin/end call --
 * do not call this (or any of those) from inside another still-open
 * path.
 */
private void roundedRectPath(bool fill, int x, int y, int w, int h, int r)
{
    if (r == 5) r = 4;
    if (r == 7) r = 8;
    double xd = x, yd = y, rd = x + w - 1, bd = y + h - 1;
    double rr = r;

    if (fill) beginPolygon(); else beginLoop();

    // top left
    transformedVertex(xd + roundedRectLut[0] * rr, yd + roundedRectLut[4] * rr);
    transformedVertex(xd + roundedRectLut[1] * rr, yd + roundedRectLut[3] * rr);
    transformedVertex(xd + roundedRectLut[2] * rr, yd + roundedRectLut[2] * rr);
    transformedVertex(xd + roundedRectLut[3] * rr, yd + roundedRectLut[1] * rr);
    transformedVertex(xd + roundedRectLut[4] * rr, yd + roundedRectLut[0] * rr);
    // top right
    transformedVertex(rd - roundedRectLut[4] * rr, yd + roundedRectLut[0] * rr);
    transformedVertex(rd - roundedRectLut[3] * rr, yd + roundedRectLut[1] * rr);
    transformedVertex(rd - roundedRectLut[2] * rr, yd + roundedRectLut[2] * rr);
    transformedVertex(rd - roundedRectLut[1] * rr, yd + roundedRectLut[3] * rr);
    transformedVertex(rd - roundedRectLut[0] * rr, yd + roundedRectLut[4] * rr);
    // bottom right
    transformedVertex(rd - roundedRectLut[0] * rr, bd - roundedRectLut[4] * rr);
    transformedVertex(rd - roundedRectLut[1] * rr, bd - roundedRectLut[3] * rr);
    transformedVertex(rd - roundedRectLut[2] * rr, bd - roundedRectLut[2] * rr);
    transformedVertex(rd - roundedRectLut[3] * rr, bd - roundedRectLut[1] * rr);
    transformedVertex(rd - roundedRectLut[4] * rr, bd - roundedRectLut[0] * rr);
    // bottom left
    transformedVertex(xd + roundedRectLut[4] * rr, bd - roundedRectLut[0] * rr);
    transformedVertex(xd + roundedRectLut[3] * rr, bd - roundedRectLut[1] * rr);
    transformedVertex(xd + roundedRectLut[2] * rr, bd - roundedRectLut[2] * rr);
    transformedVertex(xd + roundedRectLut[1] * rr, bd - roundedRectLut[3] * rr);
    transformedVertex(xd + roundedRectLut[0] * rr, bd - roundedRectLut[4] * rr);

    if (fill) endPolygon(); else endLoop();
}

/// Draws the outline of a rectangle inscribed in (x,y,w,h) with corner
/// radius r, in the current fl_color(). Ported from
/// Fl_Graphics_Driver::rounded_rect() (`fl_rounded_rect()` in
/// fl_draw.H).
void roundedRect(int x, int y, int w, int h, int r)
{
    roundedRectPath(false, x, y, w, h, r);
}

/// Draws a filled rectangle inscribed in (x,y,w,h) with corner radius
/// r, in the current fl_color(). Ported from Fl_Graphics_Driver::
/// rounded_rectf() (`roundedRectf()` in fl_draw.H).
void roundedRectf(int x, int y, int w, int h, int r)
{
    roundedRectPath(true, x, y, w, h, r);
}

unittest
{
    // roundedRect()/roundedRectf(): pure vertex-path bookkeeping,
    // no display needed. Every call produces exactly 20 points (5 per
    // corner, 4 corners), and the lookup table's 0.0/1.0 endpoints mean
    // the first/last points of the top-left corner sit exactly on the
    // box's own left edge (x) and top edge (y) respectively.
    loadIdentity();

    beginLoop();
    roundedRect(10, 20, 100, 50, 8);
    assert(vertexPoints_.length == 20);
    assert(vertexPoints_[0] == VPoint(10, 20 + 8)); // top-left corner start: (x, y+r)
    assert(vertexPoints_[4] == VPoint(10 + 8, 20));  // top-left corner end: (x+r, y)
    endLoop();

    beginPolygon();
    roundedRectf(10, 20, 100, 50, 8);
    assert(vertexPoints_.length == 20);
    endPolygon();

    // r==5 snaps to 4, r==7 snaps to 8 (FLTK's own STR #2943 fix) --
    // observable via the same corner-start/end coordinates.
    beginLoop();
    roundedRect(0, 0, 100, 100, 5);
    assert(vertexPoints_[4] == VPoint(4, 0)); // r snapped to 4, not 5
    endLoop();

    beginLoop();
    roundedRect(0, 0, 100, 100, 7);
    assert(vertexPoints_[4] == VPoint(8, 0)); // r snapped to 8, not 7
    endLoop();
}

/**
 * Computes the corner radius the "rounded" boxtype family uses for a
 * box of size (w,h) -- ported from fl_rounded_box.cxx's static `rbox()`
 * helper (the radius-clamping logic shared by all four boxtype
 * functions below, distinct from roundedRect()/roundedRectf()
 * themselves, which take an already-computed radius): about 2/5 of the
 * box's smaller dimension, clamped to fl.core.boxBorderRadiusMax().
 */
private void roundedRectClamped(bool fill, int x, int y, int w, int h)
{
    int rs = w * 2 / 5;
    int rsy = h * 2 / 5;
    if (rs > rsy) rs = rsy; // use smaller radius
    if (rs > fl.core.boxBorderRadiusMax()) rs = fl.core.boxBorderRadiusMax();
    if (fill) roundedRectf(x, y, w, h, rs);
    else roundedRect(x, y, w, h, rs);
}

/// Ported from fl_rounded_box.cxx's fl_rflat_box().
private void flRflatBox(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    roundedRectClamped(true, x, y, w, h);
    roundedRectClamped(false, x, y, w, h);
}

/// Ported from fl_rounded_box.cxx's fl_rounded_frame().
private void flRoundedFrame(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    roundedRectClamped(false, x, y, w, h);
}

/// Ported from fl_rounded_box.cxx's fl_rounded_box().
private void flRoundedBox(int x, int y, int w, int h, Color c)
{
    fl_color(c);
    roundedRectClamped(true, x, y, w, h);
    fl_color(black);
    roundedRectClamped(false, x, y, w, h);
}

/// Ported from fl_rounded_box.cxx's fl_rshadow_box().
private void flRshadowBox(int x, int y, int w, int h, Color c)
{
    int bw = fl.core.boxShadowWidth();
    fl_color(dark3);
    roundedRectClamped(true, x + bw, y + bw, w, h);
    roundedRectClamped(false, x + bw, y + bw, w, h);
    flRoundedBox(x, y, w, h, c);
}

// ---------------------------------------------------------------------
// "Gleam" scheme boxtype family (src/fl_gleam.cxx) -- core-roadmap
// item 11, Phase B, first scheme ported (smallest of the four, no
// fl.image/Fl_Tiled_Image dependency, per that item's own recommended
// order). A 2-pixel-bordered, top/bottom-gradient-shaded look ("Clear
// looks Glossy"); every boxtype here shares the same dx/dy/dw/dh (2,2,
// 4,4) -- no "thin" distinction, matching FLTK's own doc comment
// in fl_gleam.cxx and this port's existing boxTable rows for these
// (added ahead of time during Phase A scoping).
//
// DELIBERATE SIMPLIFICATION, same one already established for the
// oval/round/diamond families just above: FLTK's `gleam_color(c)`
// is `Fl::set_box_color(c)` (`fl_color(active_r/draw_it_active ? c :
// inactive(c))`); this port never ported that process-wide
// draw_it_active flag, so gleamColor() collapses to plain `fl_color(c)`
// -- active/inactive dimming stays the caller's responsibility (see the
// module note above flOvalFlatBox() for the full reasoning, which
// applies here unchanged).
//
// FLTK_ISSUES.md entry: the
// "round" gleam boxtypes (gleamRoundUpBox/gleamRoundDownBox) are wired
// in FLTK's own fl_box_table to the exact same fl_gleam_up_box/
// fl_gleam_down_box functions as the plain (non-round) gleam boxtypes
// -- there is no fl_gleam_round_up_box/fl_gleam_round_down_box at all
// in fl_gleam.cxx. So a RoundButton/RadioButton drawn with an active
// "gleam" scheme gets a square gleam box for its background, not a
// round one -- ported faithfully as-is (this is what real FLTK does
// too), not treated as something to fix here.

private void gleamColor(Color c)
{
    fl_color(c);
}

/**
 * Draws the shaded (gradient) background of a gleam box, inset 2px on
 * each side (so w/h are reduced by 4 total) -- called before the box's
 * frame/border. Ported verbatim from fl_gleam.cxx's
 * shade_rect_top_bottom(): a lightened/darkened gradient band across
 * the top (up to 20px) and bottom (up to 15px), with a flat fill of fg1
 * in between.
 */
private void gleamShadeRectTopBottom(int x, int y, int w, int h, Color fg1, Color fg2, float th)
{
    x += 2;
    y += 2;
    w -= 4;
    h -= 4;

    int hTop = (h / 2) < 20 ? (h / 2) : 20;
    int hBottom = (h / 6) < 15 ? (h / 6) : 15;
    int hFlat = h - hTop - hBottom;
    float stepTop = hTop > 1 ? (0.999f / cast(float) hTop) : 1;
    float stepBottom = hBottom > 1 ? (0.999f / cast(float) hBottom) : 1;

    float k = 1;
    foreach (i; 0 .. hTop)
    {
        gleamColor(colorAverage(colorAverage(fg1, fg2, th), fg1, k));
        fl_xyline(x, y + i, x + w - 1);
        k -= stepTop;
    }

    gleamColor(fg1);
    fl_rectf(x, y + hTop, w, hFlat);

    k = 1;
    foreach (i; 0 .. hBottom)
    {
        gleamColor(colorAverage(fg1, colorAverage(fg1, fg2, th), k));
        fl_xyline(x, y + hTop + hFlat + i, x + w - 1);
        k -= stepBottom;
    }
}

private void gleamShadeRectTopBottomUp(int x, int y, int w, int h, Color bc, float th)
{
    gleamShadeRectTopBottom(x, y, w, h, bc, white, th);
}

private void gleamShadeRectTopBottomDown(int x, int y, int w, int h, Color bc, float th)
{
    gleamShadeRectTopBottom(x, y, w, h, bc, black, th);
}

/**
 * Draws a gleam box's 2px border: fg1 is the outer line (all 4 sides),
 * fg2 the inner left/right line, lc the inner top/bottom line. Ported
 * verbatim from fl_gleam.cxx's frame_rect().
 */
private void gleamFrameRect(int x, int y, int w, int h, Color fg1, Color fg2, Color lc)
{
    gleamColor(fg1);
    fl_xyline(x + 1, y, x + w - 2);
    fl_yxline(x + w - 1, y + 1, y + h - 2);
    fl_xyline(x + 1, y + h - 1, x + w - 2);
    fl_yxline(x, y + 1, y + h - 2);

    gleamColor(fg2);
    fl_yxline(x + 1, y + 2, y + h - 3);
    fl_yxline(x + w - 2, y + 2, y + h - 3);

    gleamColor(lc);
    fl_xyline(x + 2, y + 1, x + w - 3);
    fl_xyline(x + 2, y + h - 2, x + w - 3);
}

private void gleamFrameRectUp(int x, int y, int w, int h, Color bc, Color lc, float th1, float th2)
{
    gleamFrameRect(x, y, w, h, colorAverage(darker(bc), black, th1),
        colorAverage(bc, white, th2), lc);
}

private void gleamFrameRectDown(int x, int y, int w, int h, Color bc, Color lc, float th1, float th2)
{
    gleamFrameRect(x, y, w, h, colorAverage(bc, white, th1),
        colorAverage(black, bc, th2), lc);
}

/// Ported from fl_gleam.cxx's fl_gleam_up_frame().
private void flGleamUpFrame(int x, int y, int w, int h, Color c)
{
    gleamFrameRectUp(x, y, w, h, c, colorAverage(c, white, .25f), .55f, .05f);
}

/// Ported from fl_gleam.cxx's fl_gleam_up_box().
private void flGleamUpBox(int x, int y, int w, int h, Color c)
{
    gleamShadeRectTopBottomUp(x, y, w, h, c, .15f);
    gleamFrameRectUp(x, y, w, h, c, colorAverage(c, white, .05f), .15f, .05f);
}

/// Ported from fl_gleam.cxx's fl_gleam_thin_up_box().
private void flGleamThinUpBox(int x, int y, int w, int h, Color c)
{
    gleamShadeRectTopBottomUp(x, y, w, h, c, .25f);
    gleamFrameRectUp(x, y, w, h, c, colorAverage(c, white, .45f), .25f, .15f);
}

/// Ported from fl_gleam.cxx's fl_gleam_down_frame().
private void flGleamDownFrame(int x, int y, int w, int h, Color c)
{
    gleamFrameRectDown(x, y, w, h, darker(c), darker(c), .25f, .95f);
}

/// Ported from fl_gleam.cxx's fl_gleam_down_box().
private void flGleamDownBox(int x, int y, int w, int h, Color c)
{
    gleamShadeRectTopBottomDown(x, y, w, h, c, .65f);
    gleamFrameRectDown(x, y, w, h, c, colorAverage(c, black, .05f), .05f, .95f);
}

/// Ported from fl_gleam.cxx's fl_gleam_thin_down_box().
private void flGleamThinDownBox(int x, int y, int w, int h, Color c)
{
    gleamShadeRectTopBottomDown(x, y, w, h, c, .85f);
    gleamFrameRectDown(x, y, w, h, c, colorAverage(c, black, .45f), .35f, .85f);
}

// ---------------------------------------------------------------------
// "GTK+" scheme boxtype family (src/fl_gtk.cxx) -- core-roadmap item
// 11, Phase B, second scheme family ported ("a GTK+ look, based on Red
// Hat's Bluecurve theme", FLTK's own header comment). An octagonal
// (corner-clipped-rectangle) outline drawn via the transform-stack
// `beginLoop()`/`vertex()`/`endLoop()` path, plus a solid
// beveled-circle round-button family sharing the same *shape* of helper
// as `fl.core`'s existing `roundBoxPart()` (same `{UPPER_LEFT,
// LOWER_RIGHT, CLOSED, FILL}` enum names FLTK reuses across both
// files) but NOT the same function -- FLTK's `fl_gtk.cxx` defines
// its own private `draw()`, textually similar to but subtly different
// from `fl_round_box.cxx`'s (no `w == h` quarter-circle special case in
// the UPPER_LEFT/LOWER_RIGHT branches, no `+1` on the FILL rectf, and
// color is set by the caller before each call rather than taken as a
// `draw()` parameter) -- ported here as a separate `gtkRoundBoxPart()`
// rather than reused, matching FLTK's own non-sharing exactly.
//
// Same `gtk_color()`-collapses-to-plain-`fl_color()` simplification as
// every other scheme/oval/round/diamond family in this module (FLTK's
// `Fl::set_box_color()` `draw_it_active` auto-dim flag was never ported;
// dimming stays the caller's responsibility).

private void gtkColor(Color c)
{
    fl_color(c);
}

/// Ported from fl_gtk.cxx's fl_gtk_up_frame(): a corner-clipped
/// (octagonal) outline, one darker line traced via beginLoop()/
/// vertex()/endLoop(), plus two lighter highlight segments on
/// the top/left edges.
private void flGtkUpFrame(int x, int y, int w, int h, Color c)
{
    gtkColor(colorAverage(white, c, .5f));
    fl_xyline(x + 2, y + 1, x + w - 3);
    fl_yxline(x + 1, y + 2, y + h - 3);

    gtkColor(colorAverage(black, c, .5f));
    beginLoop();
    vertex(x, y + 2);
    vertex(x + 2, y);
    vertex(x + w - 3, y);
    vertex(x + w - 1, y + 2);
    vertex(x + w - 1, y + h - 3);
    vertex(x + w - 3, y + h - 1);
    vertex(x + 2, y + h - 1);
    vertex(x, y + h - 3);
    endLoop();
}

/// Ported from fl_gtk.cxx's fl_gtk_up_box(): the up-frame outline plus
/// a 3-line lighter gradient near the top, a flat fill, and a 3-line
/// darker gradient near the bottom (the "glossy" GTK+ button look).
private void flGtkUpBox(int x, int y, int w, int h, Color c)
{
    flGtkUpFrame(x, y, w, h, c);

    gtkColor(colorAverage(white, c, .4f));
    fl_xyline(x + 2, y + 2, x + w - 3);
    gtkColor(colorAverage(white, c, .2f));
    fl_xyline(x + 2, y + 3, x + w - 3);
    gtkColor(colorAverage(white, c, .1f));
    fl_xyline(x + 2, y + 4, x + w - 3);
    gtkColor(c);
    fl_rectf(x + 2, y + 5, w - 4, h - 7);
    gtkColor(colorAverage(black, c, .025f));
    fl_xyline(x + 2, y + h - 4, x + w - 3);
    gtkColor(colorAverage(black, c, .05f));
    fl_xyline(x + 2, y + h - 3, x + w - 3);
    gtkColor(colorAverage(black, c, .1f));
    fl_xyline(x + 2, y + h - 2, x + w - 3);
    fl_yxline(x + w - 2, y + 2, y + h - 3);
}

/// Ported from fl_gtk.cxx's fl_gtk_down_frame().
private void flGtkDownFrame(int x, int y, int w, int h, Color c)
{
    gtkColor(colorAverage(black, c, .5f));
    beginLoop();
    vertex(x, y + 2);
    vertex(x + 2, y);
    vertex(x + w - 3, y);
    vertex(x + w - 1, y + 2);
    vertex(x + w - 1, y + h - 3);
    vertex(x + w - 3, y + h - 1);
    vertex(x + 2, y + h - 1);
    vertex(x, y + h - 3);
    endLoop();

    gtkColor(colorAverage(black, c, .1f));
    fl_xyline(x + 2, y + 1, x + w - 3);
    fl_yxline(x + 1, y + 2, y + h - 3);

    gtkColor(colorAverage(black, c, .05f));
    fl_yxline(x + 2, y + h - 2, y + 2, x + w - 2);
}

/// Ported from fl_gtk.cxx's fl_gtk_down_box().
private void flGtkDownBox(int x, int y, int w, int h, Color c)
{
    flGtkDownFrame(x, y, w, h, c);

    gtkColor(c);
    fl_rectf(x + 3, y + 3, w - 5, h - 4);
    fl_yxline(x + w - 2, y + 3, y + h - 3);
}

/// Ported from fl_gtk.cxx's fl_gtk_thin_up_frame().
private void flGtkThinUpFrame(int x, int y, int w, int h, Color c)
{
    gtkColor(colorAverage(white, c, .6f));
    fl_xyline(x + 1, y, x + w - 2);
    fl_yxline(x, y + 1, y + h - 2);

    gtkColor(colorAverage(black, c, .4f));
    fl_xyline(x + 1, y + h - 1, x + w - 2);
    fl_yxline(x + w - 1, y + 1, y + h - 2);
}

/// Ported from fl_gtk.cxx's fl_gtk_thin_up_box().
private void flGtkThinUpBox(int x, int y, int w, int h, Color c)
{
    flGtkThinUpFrame(x, y, w, h, c);

    gtkColor(colorAverage(white, c, .4f));
    fl_xyline(x + 1, y + 1, x + w - 2);
    gtkColor(colorAverage(white, c, .2f));
    fl_xyline(x + 1, y + 2, x + w - 2);
    gtkColor(colorAverage(white, c, .1f));
    fl_xyline(x + 1, y + 3, x + w - 2);
    gtkColor(c);
    fl_rectf(x + 1, y + 4, w - 2, h - 8);
    gtkColor(colorAverage(black, c, .025f));
    fl_xyline(x + 1, y + h - 4, x + w - 2);
    gtkColor(colorAverage(black, c, .05f));
    fl_xyline(x + 1, y + h - 3, x + w - 2);
    gtkColor(colorAverage(black, c, .1f));
    fl_xyline(x + 1, y + h - 2, x + w - 2);
}

/// Ported from fl_gtk.cxx's fl_gtk_thin_down_frame().
private void flGtkThinDownFrame(int x, int y, int w, int h, Color c)
{
    gtkColor(colorAverage(black, c, .4f));
    fl_xyline(x + 1, y, x + w - 2);
    fl_yxline(x, y + 1, y + h - 2);

    gtkColor(colorAverage(white, c, .6f));
    fl_xyline(x + 1, y + h - 1, x + w - 2);
    fl_yxline(x + w - 1, y + 1, y + h - 2);
}

/// Ported from fl_gtk.cxx's fl_gtk_thin_down_box().
private void flGtkThinDownBox(int x, int y, int w, int h, Color c)
{
    flGtkThinDownFrame(x, y, w, h, c);

    gtkColor(c);
    fl_rectf(x + 1, y + 1, w - 2, h - 2);
}

/// Which arc/pie fragment gtkRoundBoxPart() draws -- ported from
/// fl_gtk.cxx's own anonymous `{UPPER_LEFT, LOWER_RIGHT, CLOSED, FILL}`
/// enum (textually identical names to fl.core's roundUpperLeft/etc.,
/// but this is a separate, differently-behaved function -- see this
/// section's own module comment above gtkColor()).
private enum : int { gtkRoundUpperLeft, gtkRoundLowerRight, gtkRoundClosed, gtkRoundFill }

/**
 * Draws one fragment of a GTK+ round box's outline or fill, inset by
 * inset pixels, in the *current* draw color (unlike fl.core's
 * roundBoxPart(), color is set by the caller before each call here,
 * matching fl_gtk.cxx's own draw() exactly -- no `w == h` quarter-
 * circle special case in the UPPER_LEFT/LOWER_RIGHT branches, no `+1`
 * on the FILL rectf).
 */
private void gtkRoundBoxPart(int which, int x, int y, int w, int h, int inset)
{
    if (inset * 2 >= w) inset = (w - 1) / 2;
    if (inset * 2 >= h) inset = (h - 1) / 2;
    x += inset;
    y += inset;
    w -= 2 * inset;
    h -= 2 * inset;
    int d = w <= h ? w : h;
    if (d <= 1) return;
    ArcFn f = (which == gtkRoundFill) ? &fl_pie : &fl_arc;
    if (which >= gtkRoundClosed)
    {
        if (w == h) f(x, y, d, d, 0, 360);
        else
        {
            f(x + w - d, y, d, d, w <= h ? 0 : -90, w <= h ? 180 : 90);
            f(x, y + h - d, d, d, w <= h ? 180 : 90, w <= h ? 360 : 270);
        }
    }
    else if (which == gtkRoundUpperLeft)
    {
        f(x + w - d, y, d, d, 45, w <= h ? 180 : 90);
        f(x, y + h - d, d, d, w <= h ? 180 : 90, 225);
    }
    else // gtkRoundLowerRight
    {
        f(x, y + h - d, d, d, 225, w <= h ? 360 : 270);
        f(x + w - d, y, d, d, w <= h ? 360 : 270, 360 + 45);
    }
    if (which == gtkRoundFill)
    {
        if (w < h) fl_rectf(x, y + d / 2, w, h - (d & ~1));
        else if (w > h) fl_rectf(x + d / 2, y, w - (d & ~1), h);
    }
    else
    {
        if (w < h)
        {
            if (which != gtkRoundUpperLeft) fl_yxline(x + w - 1, y + d / 2 - 1, y + h - d / 2 + 1);
            if (which != gtkRoundLowerRight) fl_yxline(x, y + d / 2 - 1, y + h - d / 2 + 1);
        }
        else if (w > h)
        {
            if (which != gtkRoundUpperLeft) fl_xyline(x + d / 2 - 1, y + h - 1, x + w - d / 2 + 1);
            if (which != gtkRoundLowerRight) fl_xyline(x + d / 2 - 1, y, x + w - d / 2 + 1);
        }
    }
}

/// Ported from fl_gtk.cxx's fl_gtk_round_up_box().
private void flGtkRoundUpBox(int x, int y, int w, int h, Color c)
{
    gtkColor(c);
    gtkRoundBoxPart(gtkRoundFill, x, y, w, h, 2);

    gtkColor(colorAverage(black, c, .025f));
    gtkRoundBoxPart(gtkRoundLowerRight, x + 1, y, w - 2, h, 2);
    gtkRoundBoxPart(gtkRoundLowerRight, x, y, w, h, 3);
    gtkColor(colorAverage(black, c, .05f));
    gtkRoundBoxPart(gtkRoundLowerRight, x + 1, y, w - 2, h, 1);
    gtkRoundBoxPart(gtkRoundLowerRight, x, y, w, h, 2);
    gtkColor(colorAverage(black, c, .1f));
    gtkRoundBoxPart(gtkRoundLowerRight, x + 1, y, w - 2, h, 0);
    gtkRoundBoxPart(gtkRoundLowerRight, x, y, w, h, 1);

    gtkColor(colorAverage(white, c, .1f));
    gtkRoundBoxPart(gtkRoundUpperLeft, x, y, w, h, 4);
    gtkRoundBoxPart(gtkRoundUpperLeft, x + 1, y, w - 2, h, 3);
    gtkColor(colorAverage(white, c, .2f));
    gtkRoundBoxPart(gtkRoundUpperLeft, x, y, w, h, 3);
    gtkRoundBoxPart(gtkRoundUpperLeft, x + 1, y, w - 2, h, 2);
    gtkColor(colorAverage(white, c, .4f));
    gtkRoundBoxPart(gtkRoundUpperLeft, x, y, w, h, 2);
    gtkRoundBoxPart(gtkRoundUpperLeft, x + 1, y, w - 2, h, 1);
    gtkColor(colorAverage(white, c, .5f));
    gtkRoundBoxPart(gtkRoundUpperLeft, x, y, w, h, 1);
    gtkRoundBoxPart(gtkRoundUpperLeft, x + 1, y, w - 2, h, 0);

    gtkColor(colorAverage(black, c, .5f));
    gtkRoundBoxPart(gtkRoundClosed, x, y, w, h, 0);
}

/// Ported from fl_gtk.cxx's fl_gtk_round_down_box().
private void flGtkRoundDownBox(int x, int y, int w, int h, Color c)
{
    gtkColor(c);
    gtkRoundBoxPart(gtkRoundFill, x, y, w, h, 2);

    gtkColor(colorAverage(white, c, .1f));
    gtkRoundBoxPart(gtkRoundLowerRight, x + 1, y, w - 2, h, 2);
    gtkRoundBoxPart(gtkRoundLowerRight, x, y, w, h, 3);
    gtkColor(colorAverage(white, c, .2f));
    gtkRoundBoxPart(gtkRoundLowerRight, x + 1, y, w - 2, h, 1);
    gtkRoundBoxPart(gtkRoundLowerRight, x, y, w, h, 2);
    gtkColor(colorAverage(white, c, .5f));
    gtkRoundBoxPart(gtkRoundLowerRight, x + 1, y, w - 2, h, 0);
    gtkRoundBoxPart(gtkRoundLowerRight, x, y, w, h, 1);

    gtkColor(colorAverage(black, c, .05f));
    gtkRoundBoxPart(gtkRoundUpperLeft, x, y, w, h, 2);
    gtkRoundBoxPart(gtkRoundUpperLeft, x + 1, y, w - 2, h, 1);
    gtkColor(colorAverage(black, c, .1f));
    gtkRoundBoxPart(gtkRoundUpperLeft, x, y, w, h, 1);
    gtkRoundBoxPart(gtkRoundUpperLeft, x + 1, y, w - 2, h, 0);

    gtkColor(colorAverage(black, c, .5f));
    gtkRoundBoxPart(gtkRoundClosed, x, y, w, h, 0);
}

// ---------------------------------------------------------------------
// "Oxy" scheme boxtype family (src/fl_oxy.cxx, ~500 lines) -- one of
// the four scheme families. Wired into drawBoxAt()'s switch under the
// already-existing oxyUpBox/oxyDownBox/oxyUpFrame/oxyDownFrame/
// oxyThinUpBox/oxyThinDownBox/oxyThinUpFrame/oxyThinDownFrame/
// oxyRoundUpBox/oxyRoundDownBox/oxyButtonUpBox/oxyButtonDownBox
// Boxtype values and fl.core.boxTable metrics rows (see
// fl.core.d). Also includes oxy_arrow() (below, near the end of this
// section), the `drawArrow()`'s own `Fl::is_scheme("oxy")`
// branch (see that function's own doc comment).
//
// Unlike gtk+'s private per-file {UPPER_LEFT, LOWER_RIGHT, CLOSED,
// FILL} enum, FLTK's own oxy_draw() dispatches on the *real*
// Fl_Boxtype enum values directly (FL_OXY_UP_BOX et al. genuinely are
// Fl_Boxtype members, not a local enum) -- ported here taking a real
// Boxtype parameter to match, rather than introducing an unnecessary
// private enum.
//
// oxy_color() FLTK is a pure value-transform (returns a
// possibly-inactive()-dimmed color), not a color-setting function
// like gtk_color()/gleam_color() -- but it exists for exactly the same
// reason: gating on the process-wide `Fl::draw_box_active()` flag this
// port has never tracked (same gap already documented for every other
// scheme/oval/round/diamond family here). Ported as a passthrough that
// always takes the "active" branch, dimming staying the caller's
// responsibility like every other boxtype function in this module.

private Color oxyColor(Color c)
{
    return c;
}

/// Ported from fl_oxy.cxx's _oxy_up_box_(): a south-to-north gradient
/// (bg averaged toward white, offset increasing bottom to top).
private void oxyUpBoxGradient(int x, int y, int w, int h, Color bg)
{
    float gradoffset = 0.45f;
    float stepoffset = 1.0f / cast(float) h;
    int xw = x + w - 1;
    for (int yy = y; yy < y + h; yy++)
    {
        fl_color(colorAverage(bg, white, gradoffset < 1.0f ? gradoffset : 1.0f));
        fl_xyline(x, yy, xw);
        gradoffset += stepoffset;
    }
}

/// Ported from fl_oxy.cxx's _oxy_down_box_(): north-to-south gradient.
private void oxyDownBoxGradient(int x, int y, int w, int h, Color bg)
{
    float gradoffset = 0.45f;
    float stepoffset = 1.0f / cast(float) h;
    int xw = x + w - 1;
    for (int yy = y + h - 1; yy >= y; yy--)
    {
        fl_color(colorAverage(bg, white, gradoffset < 1.0f ? gradoffset : 1.0f));
        fl_xyline(x, yy, xw);
        gradoffset += stepoffset;
    }
}

/// Ported from fl_oxy.cxx's _oxy_button_up_box_(): a two-half gradient,
/// lighter near the top, plain bg near the bottom.
private void oxyButtonUpBoxGradient(int x, int y, int w, int h, Color bg)
{
    int halfH = h / 2;
    float gradoffset = 0.15f;
    float stepoffset = 1.0f / cast(float) halfH;
    Color col = colorAverage(bg, white, 0.5f);
    int xw = x + w - 1;
    for (int yy = y; yy <= y + halfH; yy++)
    {
        fl_color(colorAverage(col, white, gradoffset < 1.0f ? gradoffset : 1.0f));
        fl_xyline(x, yy, xw);
        gradoffset += stepoffset;
    }
    gradoffset = 0.0f;
    col = bg;
    for (int yy = y + h - 1; yy >= y + halfH - 1; yy--)
    {
        fl_color(colorAverage(col, white, gradoffset < 1.0f ? gradoffset : 1.0f));
        fl_xyline(x, yy, xw);
        gradoffset += stepoffset;
    }
}

/// Ported from fl_oxy.cxx's _oxy_button_down_box_(): same shape as the
/// button-up gradient, but bg is pre-darkened toward black first.
private void oxyButtonDownBoxGradient(int x, int y, int w, int h, Color bg)
{
    bg = colorAverage(bg, black, 0.88f);
    int halfH = h / 2;
    int xw = x + w - 1;
    float gradoffset = 0.15f;
    float stepoffset = 1.0f / cast(float) halfH;
    Color col = colorAverage(bg, white, 0.5f);
    for (int yy = y; yy <= y + halfH; yy++)
    {
        fl_color(colorAverage(col, white, gradoffset < 1.0f ? gradoffset : 1.0f));
        fl_xyline(x, yy, xw);
        gradoffset += stepoffset;
    }
    gradoffset = 0.0f;
    col = bg;
    for (int yy = y + h - 1; yy >= y + halfH - 1; yy--)
    {
        fl_color(colorAverage(col, white, gradoffset < 1.0f ? gradoffset : 1.0f));
        fl_xyline(x, yy, xw);
        gradoffset += stepoffset;
    }
}

/// Ported from fl_oxy.cxx's _oxy_rounded_box_(): a filled stadium/pill
/// shape (or a plain circle when w == h) -- same three-piece
/// pie+rect+pie construction as fl.core's roundBoxPart()/fl_gtk.cxx's
/// own round family, but self-contained since oxy's round boxtypes are
/// filled in one shot rather than drawn as a separate outline/fill
/// pair.
private void oxyRoundedBoxFill(int x, int y, int w, int h, Color bg)
{
    fl_color(bg);
    if (w > h)
    {
        fl_pie(x, y, h, h, 90.0, 270.0);
        fl_rectf(x + h / 2, y, w - h + 1, h);
        fl_pie(x + w - h, y, h, h, 0.0, 90.0);
        fl_pie(x + w - h, y, h, h, 270.0, 360.0);
    }
    else if (w == h)
    {
        fl_pie(x, y, w, w, 0.0, 360.0);
    }
    else
    {
        fl_pie(x, y, w, w, 0.0, 180.0);
        fl_rectf(x, y + w / 2, w, h - w + 1);
        fl_pie(x, y + h - w, w, w, 180.0, 360.0);
    }
}

/**
 * Draws one oxy box/frame variant of typebox at (x,y,w,h) in color
 * col, with or without the outer drop-shadow highlight pass. Ported
 * from fl_oxy.cxx's oxy_draw() -- the shared dispatch every fl_oxy_*()
 * public wrapper below funnels through, matching FLTK's own
 * structure (a single typebox-dispatching draw() plus twelve thin
 * wrappers) exactly.
 */
private void oxyDraw(int x, int y, int w, int h, Color col, Boxtype typebox, bool isShadow)
{
    if (w < 1 || h < 1) return;
    int X, Y, W, H;

    // draw bg
    if (typebox != Boxtype.oxyUpFrame && typebox != Boxtype.oxyDownFrame)
    {
        X = x + 1;
        Y = y + 1;
        W = w - 2;
        H = h - 2;

        switch (typebox)
        {
        case Boxtype.oxyUpBox:
            oxyUpBoxGradient(X, Y, W, H, oxyColor(col));
            break;
        case Boxtype.oxyDownBox:
            oxyDownBoxGradient(X, Y, W, H, oxyColor(col));
            break;
        case Boxtype.oxyButtonUpBox:
            oxyButtonUpBoxGradient(X, Y, W, H, oxyColor(col));
            break;
        case Boxtype.oxyButtonDownBox:
            oxyButtonDownBoxGradient(X, Y, W, H, oxyColor(col));
            break;
        case Boxtype.oxyRoundUpBox:
        case Boxtype.oxyRoundDownBox:
            oxyRoundedBoxFill(x, y, w, h, oxyColor(colorAverage(col, white, 0.82f)));
            break;
        default:
            break;
        }
    }

    Color leftline = col, topline = col, rightline = col, bottomline = col;

    if (typebox == Boxtype.oxyRoundUpBox || typebox == Boxtype.oxyRoundDownBox)
    {
        leftline = colorAverage(col, white, 0.88f);
        leftline = topline = rightline = bottomline = colorAverage(leftline, black, 0.97f);
    }
    else if (typebox == Boxtype.oxyUpBox || typebox == Boxtype.oxyUpFrame)
    {
        topline = colorAverage(col, black, 0.95f);
        leftline = colorAverage(col, black, 0.85f);
        rightline = leftline;
        bottomline = colorAverage(col, black, 0.88f);
    }
    else if (typebox == Boxtype.oxyDownBox || typebox == Boxtype.oxyDownFrame)
    {
        topline = colorAverage(col, black, 0.88f);
        leftline = colorAverage(col, black, 0.85f);
        rightline = leftline;
        bottomline = colorAverage(col, black, 0.95f);
    }
    else if (typebox == Boxtype.oxyButtonUpBox || typebox == Boxtype.oxyButtonDownBox)
    {
        topline = leftline = rightline = bottomline = colorAverage(col, black, 0.85f);
    }

    // draw border
    if (typebox != Boxtype.oxyRoundUpBox && typebox != Boxtype.oxyRoundDownBox)
    {
        fl_color(oxyColor(bottomline));
        fl_line(x + 1, y + h - 1, x + w - 2, y + h - 1);
        fl_color(oxyColor(rightline));
        fl_line(x + w - 1, y + 1, x + w - 1, y + h - 2);
        fl_color(oxyColor(topline));
        fl_line(x + 1, y, x + w - 2, y);
        fl_color(oxyColor(leftline));
        fl_line(x, y + 1, x, y + h - 2);
    }

    // draw shadow
    if (isShadow)
    {
        if (typebox == Boxtype.oxyRoundUpBox)
        {
            topline = colorAverage(col, white, 0.35f);
            bottomline = colorAverage(col, black, 0.94f);
        }
        else if (typebox == Boxtype.oxyRoundDownBox)
        {
            topline = colorAverage(col, black, 0.94f);
            bottomline = colorAverage(col, white, 0.35f);
        }
        else if (typebox == Boxtype.oxyUpBox || typebox == Boxtype.oxyUpFrame)
        {
            topline = colorAverage(col, white, 0.35f);
            leftline = colorAverage(col, white, 0.4f);
            rightline = leftline;
            bottomline = colorAverage(col, black, 0.8f);
        }
        else if (typebox == Boxtype.oxyDownBox || typebox == Boxtype.oxyDownFrame)
        {
            topline = colorAverage(col, black, 0.8f);
            leftline = colorAverage(col, black, 0.94f);
            rightline = leftline;
            bottomline = colorAverage(col, white, 0.35f);
        }

        int xw1 = x + w - 1;
        int xw2 = x + w - 2;
        int xw3 = x + w - 3;
        int yh2 = y + h - 2;
        int yh1 = y + h - 1;

        if (typebox == Boxtype.oxyUpBox || typebox == Boxtype.oxyUpFrame)
        {
            fl_color(oxyColor(topline));
            fl_line(x + 1, y + 1, xw2, y + 1); // top line

            fl_color(oxyColor(leftline));
            fl_line(x + 1, yh2, x + 1, y + 2); // left line

            fl_color(oxyColor(rightline));
            fl_line(xw2, y + 2, xw2, yh2); // right line

            fl_color(oxyColor(bottomline));
            fl_line(xw2, yh2, x + 1, yh2); // bottom line
        }
        else if (typebox == Boxtype.oxyDownBox || typebox == Boxtype.oxyDownFrame)
        {
            fl_color(oxyColor(topline));
            fl_line(x + 1, y + 1, xw2, y + 1); // top line

            fl_color(oxyColor(leftline));
            fl_line(x + 1, yh2, x + 1, y + 2); // left line

            fl_color(oxyColor(rightline));
            fl_line(xw2, y + 2, xw2, yh2); // right line

            fl_color(oxyColor(bottomline));
            fl_line(xw3, yh2, x + 2, yh2); // bottom line
        }
        else if (typebox == Boxtype.oxyRoundUpBox || typebox == Boxtype.oxyRoundDownBox)
        {
            int radius, smooth, rOffset2;

            smooth = w > h ? w : h;
            if (smooth > 0 && (smooth * 3 > w || smooth * 3 > h))
                smooth = h < w ? h / 3 : w / 3;

            rOffset2 = smooth / 2;
            radius = smooth * 3;
            if (radius == 3) radius = 4;

            fl_color(oxyColor(topline));
            fl_line(x + 1, yh1 - smooth - rOffset2, x + 1, y + rOffset2 + smooth); // left side
            fl_arc(x + 1, y + 1, radius, radius, 90.0, 180.0); // left-top corner
            if (typebox == Boxtype.oxyRoundDownBox)
                fl_arc(x + 1, y + 1, radius + 1, radius + 1, 90.0, 180.0); // left-top corner (DOWN_BOX)
            fl_line(x + smooth + rOffset2, y + 1, xw1 - smooth - rOffset2, y + 1); // top side
            fl_arc(xw1 - radius, y + 1, radius, radius, 0.0, 90.0); // right-top corner
            if (typebox == Boxtype.oxyRoundDownBox)
                fl_arc(xw1 - radius, y + 1, radius + 1, radius + 1, 0.0, 90.0); // right-top corner (DOWN_BOX)
            fl_line(xw2, y + smooth + rOffset2, xw2, yh1 - smooth - rOffset2); // right side
            fl_arc(x + 1, yh1 - radius, radius, radius, 180.0, 200.0); // left-bottom corner
            fl_arc(xw1 - radius, yh1 - radius, radius, radius, 340.0, 360.0); // right-bottom
            fl_color(oxyColor(bottomline));
            fl_arc(x + 1, yh1 - radius, radius, radius, 200.0, 270.0); // left-bottom corner
            if (typebox == Boxtype.oxyRoundUpBox)
                fl_arc(x + 1, yh1 - radius, radius + 1, radius + 1, 200.0, 270.0); // left-bottom corner (UP_BOX)
            fl_line(xw1 - smooth - rOffset2, yh2, x + smooth + rOffset2, yh2); // bottom side
            fl_arc(xw1 - radius, yh1 - radius, radius, radius, 270.0, 340.0); // right-bottom corner
            if (typebox == Boxtype.oxyRoundUpBox)
                fl_arc(xw1 - radius, yh1 - radius, radius + 1, radius + 1, 270.0, 340.0); // right-bottom corner
        }
    }
}

private void flOxyButtonUpBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyButtonUpBox, true);
}
private void flOxyButtonDownBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyButtonDownBox, true);
}
private void flOxyUpBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyUpBox, true);
}
private void flOxyDownBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyDownBox, true);
}
/// Note: matches FLTK's fl_oxy_thin_up_box() exactly -- reuses the
/// plain FL_OXY_UP_BOX dispatch with isShadow=false, not a distinct
/// "thin" typebox branch inside oxyDraw() (there is none FLTK
/// either).
private void flOxyThinUpBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyUpBox, false);
}
private void flOxyThinDownBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyDownBox, false);
}
private void flOxyUpFrame(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyUpFrame, true);
}
private void flOxyDownFrame(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyDownFrame, true);
}
private void flOxyThinUpFrame(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyUpFrame, false);
}
private void flOxyThinDownFrame(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyDownFrame, false);
}
private void flOxyRoundUpBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyRoundUpBox, true);
}
private void flOxyRoundDownBox(int x, int y, int w, int h, Color col)
{
    oxyDraw(x, y, w, h, col, Boxtype.oxyRoundDownBox, true);
}

/// Ported from fl_oxy.cxx's single_arrow(): draws one small chevron
/// (like '>') centered in bb, rotated to face o, via the transform-
/// stack + complex-polygon vertex path (pushMatrix()/
/// fl_translate()/fl_rotate()/beginComplexPolygon()/vertex()/
/// endComplexPolygon()/popMatrix()).
private void oxySingleArrow(Rect bb, Orientation o, Color col)
{
    int x1 = bb.x();
    int y1 = bb.y();
    int w1 = bb.w();
    int h1 = bb.h();

    float angle = cast(int) o * 45.0f;

    int dx = (w1 - 3) / 2;
    if (h1 < w1) dx = (h1 - 3) / 2;
    if (dx > 4) dx = 4;
    else if (dx < 2) dx = 2;

    int tx = x1 + w1 / 2;
    int ty = y1 + h1 / 2;

    enum lw = 2; // arrow line width: n+1 pixels (must be even)
    enum dw = 1; // half the line width

    fl_color(col);
    lineStyle(lineSolid, 1);
    pushMatrix();

    fl_translate(tx, ty); // move to center
    fl_rotate(angle); // rotate by given angle

    beginComplexPolygon();
    vertex(-dx + dw,      -dx);
    vertex(   0 + dw,       0);
    vertex(-dx + dw,       dx);
    vertex(-dx + dw + lw,  dx);
    vertex(   0 + dw + lw,  0);
    vertex(-dx + dw + lw, -dx);
    endComplexPolygon();

    popMatrix();
    lineStyle(0);
}

/**
 * Draws an "arrow" GUI element for the "oxy" scheme -- one or two
 * chevrons depending on t. Ported from fl_oxy.cxx's oxy_arrow(); this
 * is drawArrow()'s dedicated oxy-scheme replacement for
 * drawArrowSingle()/drawArrowDouble()/drawArrowChoice() above, a wholly
 * separate implementation rather than a small isScheme()-gated branch
 * inside them, matching FLTK's own structure exactly.
 */
private void oxyArrow(Rect bb, ArrowType t, Orientation o, Color col)
{
    switch (t)
    {
    case ArrowType.arrowDouble:
        switch (o)
        {
        case Orientation.orientDown:
        case Orientation.orientUp:
            bb.h(bb.h() - 4); // reduce size
            oxySingleArrow(bb, o, col);
            bb.y(bb.y() + 4); // shift down
            oxySingleArrow(bb, o, col);
            break;
        default:
            bb.w(bb.w() - 4); // reduce size
            oxySingleArrow(bb, o, col);
            bb.x(bb.x() + 4); // shift right
            oxySingleArrow(bb, o, col);
            break;
        }
        break;

    case ArrowType.arrowChoice:
        bb.y(bb.y() - 1); // shift upwards
        bb.h(bb.h() - 4); // reduce height
        oxySingleArrow(bb, Orientation.orientUp, col);
        bb.y(bb.y() + 6); // shift down
        oxySingleArrow(bb, Orientation.orientDown, col);
        break;

    default:
        oxySingleArrow(bb, o, col);
        break;
    }
}

// ---------------------------------------------------------------------
// "Plastic" scheme boxtype family (src/fl_plastic.cxx, 376 lines) --
// one of the four scheme families. The *scheme itself* also has a
// tiled window-background image (`Fl_Tiled_Image`, real too -- see
// `fl.core`'s row: "The 'plastic' scheme's
// `Fl_Tiled_Image` window-background tile"), separate from the
// boxtype-drawing functions below, which never had any
// `fl.image` dependency.
//
// Wired into `fl.draw.drawBoxAt()`'s switch under the already-existing
// `plasticUpBox`/`plasticDownBox`/`plasticUpFrame`/`plasticDownFrame`/
// `plasticThinUpBox`/`plasticThinDownBox`/`plasticRoundUpBox`/
// `plasticRoundDownBox` `Boxtype` values and `fl.core.boxTable` metrics
// rows (both already in place from Phase A scoping, nothing new needed
// there -- see `fl.core.d`).
//
// Each of the 8 public `fl_plastic_*()` functions FLTK encodes its
// particular bevel as a short string of letters ("RVQNOPQRSTUVWVQ" and
// similar) -- each letter indexes a shade of gray via `fl_gray_ramp()`
// (this port's `grayRampChar()`, defined above near `fl_frame()`), so
// the string itself *is* the gradient/bevel profile, walked a
// character at a time by `plasticFrameRect()`/`plasticFrameRound()`/
// `plasticShadeRect()`/`plasticShadeRound()` below. Ported verbatim,
// including the pointer-arithmetic-style `c[i] - 2` shifts (index two
// letters earlier in the alphabet for a lighter/darker companion
// shade) -- these aren't a separate lookup, just `shadeColor()` called
// with a different character.

/// Ported from `Fl_Scheme::plastic_color_average()`'s private
/// module-static state + `set_color_average()`: a user-settable
/// "how gray" knob for every plastic-scheme color, clamped to [10,100]
/// percent, defaulting to 75 (the FLTK 1.4-compatible look) unless
/// overridden by `FLTK_PLASTIC_AVERAGE` or a direct call to
/// `plasticColorAverage()` below. `-1.0f` is the "not yet resolved"
/// sentinel, matching FLTK's own `-1.00f` init.
private float plasticAverage_ = -1.0f;
private enum plasticAverageMin = 10;
private enum plasticAverageDefault = 75;
private enum plasticAverageMax = 100;

private void setPlasticColorAverage(int av)
{
    if (av < plasticAverageMin) plasticAverage_ = plasticAverageMin / 100.0f;
    else if (av > plasticAverageMax) plasticAverage_ = plasticAverageMax / 100.0f;
    else plasticAverage_ = av / 100.0f;
}

/**
 * Sets the "plastic" scheme's color-average value in percent (clamped
 * to [10, 100], default 75). Ported from `Fl_Scheme::
 * plastic_color_average(int)`. Higher values make plastic-scheme
 * colors look "more gray"; lower values keep more of the original
 * widget color. Homed here rather than a dedicated `fl.scheme` module
 * since `Fl_Scheme` itself has no real D port yet (`PORTING.md`'s
 * `FL/Fl_Scheme.H` row) and this is the only piece of it this port
 * currently needs -- same reasoning `fl.draw`'s `gtkColor()`/
 * `gleamColor()`/`oxyColor()` already establish for keeping small
 * scheme-specific pieces local to the family that needs them.
 */
void plasticColorAverage(int av)
{
    setPlasticColorAverage(av);
}

/// Ported from `fl_plastic.cxx`'s own module-static
/// `plastic_color_average()` getter: lazily resolves from
/// `FLTK_PLASTIC_AVERAGE` (once) unless `plasticColorAverage()` was
/// already called directly, which always takes precedence, matching
/// FLTK. FLTK's `atoi()` returns 0 (then gets clamped to the
/// minimum) on a non-numeric environment value rather than erroring;
/// ported here as a lenient leading-digits parse that falls back to 0
/// on total failure, same effective behavior.
private float currentPlasticAverage()
{
    if (plasticAverage_ < 0.0f)
    {
        import std.process : environment;
        auto envVar = environment.get("FLTK_PLASTIC_AVERAGE");
        if (envVar.length != 0)
        {
            import std.conv : parse;
            int temp;
            try
            {
                string s = envVar;
                temp = parse!int(s);
            }
            catch (Exception)
            {
                temp = 0;
            }
            setPlasticColorAverage(temp);
        }
        else
        {
            plasticAverage_ = plasticAverageDefault / 100.0f;
        }
    }
    return plasticAverage_;
}

/// Ported from `fl_plastic.cxx`'s `shade_color()`: averages the
/// gray-ramp shade named by letter c toward base color bc, weighted by
/// `currentPlasticAverage()`.
private Color shadeColor(char c, Color bc)
{
    return colorAverage(grayRampChar(c), bc, currentPlasticAverage());
}

/// Ported from `fl_plastic.cxx`'s `frame_rect()`: a beveled rectangular
/// frame, walking inward one pixel per iteration, 4 shades (bottom/
/// right/top/left) per circuit, one iteration per 4 characters of c.
private void plasticFrameRect(int x, int y, int w, int h, string c, Color bc)
{
    int b = cast(int) c.length / 4 + 1;
    size_t ci = 0;

    x += b;
    y += b;
    w -= 2 * b;
    h -= 2 * b;
    for (; b > 1; b--)
    {
        fl_color(shadeColor(c[ci++], bc));
        fl_line(x, y + h + b, x + w - 1, y + h + b, x + w + b - 1, y + h);
        fl_color(shadeColor(c[ci++], bc));
        fl_line(x + w + b - 1, y + h, x + w + b - 1, y, x + w - 1, y - b);
        fl_color(shadeColor(c[ci++], bc));
        fl_line(x + w - 1, y - b, x, y - b, x - b, y);
        fl_color(shadeColor(c[ci++], bc));
        fl_line(x - b, y, x - b, y + h, x, y + h + b);
    }
}

/// Ported from `fl_plastic.cxx`'s `frame_round()`: the round-boxtype
/// equivalent of `plasticFrameRect()` -- three shapes depending on
/// aspect ratio (square/wide/tall), each walking inward one pixel per
/// iteration.
private void plasticFrameRound(int x, int y, int w, int h, string c, Color bc)
{
    size_t b = c.length / 4 + 1;
    size_t ci = 0;

    if (w == h)
    {
        for (; b > 1; b--, x++, y++, w -= 2, h -= 2)
        {
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, w, h, 45.0, 135.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, w, h, 315.0, 405.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, w, h, 225.0, 315.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, w, h, 135.0, 225.0);
        }
    }
    else if (w > h)
    {
        int d = h / 2;
        for (; b > 1; d--, b--, x++, y++, w -= 2, h -= 2)
        {
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, h, h, 90.0, 135.0);
            fl_xyline(x + d, y, x + w - d);
            fl_arc(x + w - h, y, h, h, 45.0, 90.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x + w - h, y, h, h, 315.0, 405.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x + w - h, y, h, h, 270.0, 315.0);
            fl_xyline(x + d, y + h - 1, x + w - d);
            fl_arc(x, y, h, h, 225.0, 270.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, h, h, 135.0, 225.0);
        }
    }
    else // w < h
    {
        int d = w / 2;
        for (; b > 1; d--, b--, x++, y++, w -= 2, h -= 2)
        {
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, w, w, 45.0, 135.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y, w, w, 0.0, 45.0);
            fl_yxline(x + w - 1, y + d, y + h - d);
            fl_arc(x, y + h - w, w, w, 315.0, 360.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y + h - w, w, w, 225.0, 315.0);
            fl_color(shadeColor(c[ci++], bc));
            fl_arc(x, y + h - w, w, w, 180.0, 225.0);
            fl_yxline(x, y + d, y + h - d);
            fl_arc(x, y, w, w, 135.0, 180.0);
        }
    }
}

/// Ported from `fl_plastic.cxx`'s `shade_rect()`: the filled-interior
/// gradient behind a plastic box's frame, choosing horizontal vs.
/// vertical shading bands based on aspect ratio. `c[i] - 2` (two
/// letters earlier in the alphabet) picks a lighter/darker companion
/// shade for the single corner pixels flanking each band, not a
/// separate lookup -- see this section's own header comment.
private void plasticShadeRect(int x, int y, int w, int h, string c, Color bc)
{
    int clen = cast(int) c.length - 1;
    int chalf = clen / 2;
    int cstep = 1;
    int i, j;

    if (h < w * 2)
    {
        // Horizontal shading...
        if (clen >= h) cstep = 2;

        for (i = 0, j = 0; j < chalf; i++, j += cstep)
        {
            fl_color(shadeColor(c[i], bc));
            fl_xyline(x + 1, y + i, x + w - 2);

            fl_color(shadeColor(cast(char)(c[i] - 2), bc));
            point(x, y + i + 1);
            point(x + w - 1, y + i + 1);

            fl_color(shadeColor(c[clen - i], bc));
            fl_xyline(x + 1, y + h - i, x + w - 2);

            fl_color(shadeColor(cast(char)(c[clen - i] - 2), bc));
            point(x, y + h - i);
            point(x + w - 1, y + h - i);
        }

        i = chalf / cstep;

        fl_color(shadeColor(c[chalf], bc));
        fl_rectf(x + 1, y + i, w - 2, h - 2 * i + 1);

        fl_color(shadeColor(cast(char)(c[chalf] - 2), bc));
        fl_yxline(x, y + i, y + h - i);
        fl_yxline(x + w - 1, y + i, y + h - i);
    }
    else
    {
        // Vertical shading...
        if (clen >= w) cstep = 2;

        for (i = 0, j = 0; j < chalf; i++, j += cstep)
        {
            fl_color(shadeColor(c[i], bc));
            fl_yxline(x + i, y + 1, y + h - 1);

            fl_color(shadeColor(cast(char)(c[i] - 2), bc));
            point(x + i + 1, y);
            point(x + i + 1, y + h);

            fl_color(shadeColor(c[clen - i], bc));
            fl_yxline(x + w - 1 - i, y + 1, y + h - 1);

            fl_color(shadeColor(cast(char)(c[clen - i] - 2), bc));
            point(x + w - 2 - i, y);
            point(x + w - 2 - i, y + h);
        }

        i = chalf / cstep;

        fl_color(shadeColor(c[chalf], bc));
        fl_rectf(x + i, y + 1, w - 2 * i, h - 1);

        fl_color(shadeColor(cast(char)(c[chalf] - 2), bc));
        fl_xyline(x + i, y, x + w - i);
        fl_xyline(x + i, y + h, x + w - i);
    }
}

/// Ported from `fl_plastic.cxx`'s `shade_round()`: the round-boxtype
/// equivalent of `plasticShadeRect()` -- two shapes depending on aspect
/// ratio (wide/tall vs. narrow/square), built from `fl_pie()` wedges at
/// slowly-widening angles (`na = 8` degrees per step) rather than
/// `plasticShadeRect()`'s straight scanlines.
private void plasticShadeRound(int x, int y, int w, int h, string c, Color bc)
{
    int clen = cast(int) c.length - 1;
    int chalf = clen / 2;
    enum na = 8;

    if (w > h)
    {
        int d = h / 2;
        for (int i = 0; i < chalf; i++, d--, x++, y++, w -= 2, h -= 2)
        {
            fl_color(shadeColor(c[i], bc));
            fl_pie(x, y, h, h, 90.0, 135.0 + i * na);
            fl_xyline(x + d, y, x + w - d);
            fl_pie(x + w - h, y, h, h, 45.0 + i * na, 90.0);
            fl_color(shadeColor(cast(char)(c[i] - 2), bc));
            fl_pie(x + w - h, y, h, h, 315.0 + i * na, 405.0 + i * na);
            fl_color(shadeColor(c[clen - i], bc));
            fl_pie(x + w - h, y, h, h, 270.0, 315.0 + i * na);
            fl_xyline(x + d, y + h - 1, x + w - d);
            fl_pie(x, y, h, h, 225.0 + i * na, 270.0);
            fl_color(shadeColor(cast(char)(c[clen - i] - 2), bc));
            fl_pie(x, y, h, h, 135.0 + i * na, 225.0 + i * na);
        }
        fl_color(shadeColor(c[chalf], bc));
        fl_rectf(x + d, y, w - h + 1, h + 1);
        fl_pie(x, y, h, h, 90.0, 270.0);
        fl_pie(x + w - h, y, h, h, 270.0, 90.0);
    }
    else
    {
        int d = w / 2;
        for (int i = 0; i < chalf; i++, d--, x++, y++, w -= 2, h -= 2)
        {
            fl_color(shadeColor(c[i], bc));
            fl_pie(x, y, w, w, 45.0 + i * na, 135.0 + i * na);
            fl_color(shadeColor(cast(char)(c[i] - 2), bc));
            fl_pie(x, y, w, w, 0.0, 45.0 + i * na);
            fl_yxline(x + w - 1, y + d, y + h - d);
            fl_pie(x, y + h - w, w, w, 315.0 + i * na, 360.0);
            fl_color(shadeColor(c[clen - i], bc));
            fl_pie(x, y + h - w, w, w, 225.0 + i * na, 315.0 + i * na);
            fl_color(shadeColor(cast(char)(c[clen - i] - 2), bc));
            fl_pie(x, y + h - w, w, w, 180.0, 225.0 + i * na);
            fl_yxline(x, y + d, y + h - d);
            fl_pie(x, y, w, w, 135.0 + i * na, 180.0);
        }
        fl_color(shadeColor(c[chalf], bc));
        fl_rectf(x, y + d, w + 1, h - w + 1);
        fl_pie(x, y, w, w, 0.0, 180.0);
        fl_pie(x, y + h - w, w, w, 180.0, 360.0);
    }
}

/// Ported from `fl_plastic.cxx`'s `narrow_thin_box()`: the too-small-
/// for-a-real-bevel fallback every thin/down box drops into below its
/// own minimum-size threshold -- a flat fill plus a single 1px frame,
/// no gradient.
private void narrowThinBox(int x, int y, int w, int h, Color c)
{
    if (h <= 0 || w <= 0) return;
    fl_color(shadeColor('R', c));
    fl_rectf(x + 1, y + 1, w - 2, h - 2);
    fl_color(shadeColor('I', c));
    if (w > 1)
    {
        fl_xyline(x + 1, y, x + w - 2);
        fl_xyline(x + 1, y + h - 1, x + w - 2);
    }
    if (h > 1)
    {
        fl_yxline(x, y + 1, y + h - 2);
        fl_yxline(x + w - 1, y + 1, y + h - 2);
    }
}

private void flPlasticUpFrame(int x, int y, int w, int h, Color c)
{
    plasticFrameRect(x, y, w, h - 1, "KLDIIJLM", c);
}

private void flPlasticThinUpBox(int x, int y, int w, int h, Color c)
{
    if (w > 4 && h > 4)
    {
        plasticShadeRect(x + 1, y + 1, w - 2, h - 3, "RQOQSUWQ", c);
        plasticFrameRect(x, y, w, h - 1, "IJLM", c);
    }
    else
    {
        narrowThinBox(x, y, w, h, c);
    }
}

private void flPlasticUpBox(int x, int y, int w, int h, Color c)
{
    if (w > 8 && h > 8)
    {
        plasticShadeRect(x + 1, y + 1, w - 2, h - 3, "RVQNOPQRSTUVWVQ", c);
        plasticFrameRect(x, y, w, h - 1, "IJLM", c);
    }
    else
    {
        flPlasticThinUpBox(x, y, w, h, c);
    }
}

private void flPlasticUpRound(int x, int y, int w, int h, Color c)
{
    plasticShadeRound(x, y, w, h, "RVQNOPQRSTUVWVQ", c);
    plasticFrameRound(x, y, w, h, "IJLM", c);
}

private void flPlasticDownFrame(int x, int y, int w, int h, Color c)
{
    plasticFrameRect(x, y, w, h - 1, "LLLLTTRR", c);
}

private void flPlasticDownBox(int x, int y, int w, int h, Color c)
{
    if (w > 6 && h > 6)
    {
        plasticShadeRect(x + 2, y + 2, w - 4, h - 5, "STUVWWWVT", c);
        flPlasticDownFrame(x, y, w, h, c);
    }
    else
    {
        narrowThinBox(x, y, w, h, c);
    }
}

private void flPlasticDownRound(int x, int y, int w, int h, Color c)
{
    plasticShadeRound(x, y, w, h, "STUVWWWVT", c);
    plasticFrameRound(x, y, w, h, "IJLM", c);
}

/**
 * Draws a box of type t at (x,y,w,h) in color c -- the D equivalent of
 * looking up and calling `fl_box_table[t].f` FLTK, except as a
 * direct switch rather than a real function-pointer table (FLTK's
 * table also supports runtime-registered FL_FREE_BOXTYPE custom box
 * types via Fl::set_boxtype(); not supported here). See the module
 * section note above for which boxtypes are actually covered.
 *
 * Resolves t through `fl.core.resolveBoxtype()` first (core-roadmap
 * item 11 Phase A) -- e.g. under an active "gtk+" scheme, a widget's
 * plain `Boxtype.upBox` draws as `gtkUpBox` instead, with no change
 * needed at any call site. Until a scheme's own boxtype family is
 * ported, activating that scheme just means the aliased boxtype hits
 * this switch's own `default:` (no-op) case -- the same behavior any
 * not-yet-covered boxtype already has. All four scheme families --
 * "gleam", "gtk+", "oxy", and now "plastic" -- are ported
 * (core-roadmap item 11 Phase B complete); no boxtype falls through
 * to `default:` because of a missing scheme family anymore.
 */
/// Fluid's own "Show Ghosted FlGroup Outlines" editor toggle (`fluid/
/// panels/settings_panel.fl`'s General tab) -- the direct equivalent
/// of FLTK's `Overlay_Window::draw()` temporarily swapping out
/// `FL_FLAT_BOX`'s registered drawing function for `fd_flat_box_
/// ghosted()` (`Fl::set_boxtype(FL_FLAT_BOX, fd_flat_box_ghosted, ...)`,
/// `nodes/Window_Node.cxx`) around the one call that redraws the
/// currently-edited window, then restoring it. This port's `drawBoxAt()`
/// is a direct `switch`, not a real function-pointer table (see that
/// function's own doc comment), so there's no separate function to
/// swap -- a plain global flag, consulted only by the `flatBox` case
/// below, gets the same effect: any flat-boxed widget drawn while this
/// is `true` gets a contrasting outline on top of its normal fill, and
/// nothing does otherwise. `fluid.canvas.ProjectCanvas.draw()` is the
/// only intended setter, `true` only around its own `super.draw()`
/// call -- exactly matching FLTK's save/restore-around-one-draw-
/// call scope, so no other window (Settings dialog, widget bin, ...)
/// is ever affected.
bool ghostFlatBox;

/// Public: matches FLTK's own
/// public global `fl_draw_box()` (`FL/fl_draw.H`), which custom-drawn
/// widgets (e.g. a `Table`/`Tree` subclass overriding cell/item
/// drawing) call directly, same as `fl_color()`/`fl_rect()`.
void drawBoxAt(Boxtype t, int x, int y, int w, int h, Color c)
{
    t = fl.core.resolveBoxtype(t);
    switch (t)
    {
    case Boxtype.noBox:
        break;
    case Boxtype.flatBox:
        fl_color(c);
        fl_rectf(x, y, w, h);
        // FLTK: `fd_flat_box_ghosted()`'s own trailing outline --
        // `Fl::box_color(fl_color_average(FL_FOREGROUND_COLOR, c, .1f))`.
        // `Fl::box_color()` itself isn't ported (see this project's own
        // module-map note on `gleam_color()`/`Fl::set_box_color()`: it
        // only auto-dims for inactive widgets via a process-wide flag
        // this port never tracks, dimming staying each caller's own
        // job) -- plain `c` substitutes, matching every other boxtype
        // case in this function already.
        if (ghostFlatBox)
        {
            fl_color(colorAverage(foregroundColor, c, 0.1f));
            fl_rect(x, y, w, h);
        }
        break;
    case Boxtype.upBox:
        flUpBox(x, y, w, h, c);
        break;
    case Boxtype.downBox:
        flDownBox(x, y, w, h, c);
        break;
    case Boxtype.upFrame:
        flUpFrame(x, y, w, h);
        break;
    case Boxtype.downFrame:
        flDownFrame(x, y, w, h);
        break;
    case Boxtype.thinUpBox:
        flThinUpBox(x, y, w, h, c);
        break;
    case Boxtype.thinDownBox:
        flThinDownBox(x, y, w, h, c);
        break;
    case Boxtype.thinUpFrame:
        flThinUpFrame(x, y, w, h);
        break;
    case Boxtype.thinDownFrame:
        flThinDownFrame(x, y, w, h);
        break;
    case Boxtype.engravedBox:
        flEngravedBox(x, y, w, h, c);
        break;
    case Boxtype.embossedBox:
        flEmbossedBox(x, y, w, h, c);
        break;
    case Boxtype.engravedFrame:
        flEngravedFrame(x, y, w, h);
        break;
    case Boxtype.embossedFrame:
        flEmbossedFrame(x, y, w, h);
        break;
    case Boxtype.borderBox:
        rectbound(x, y, w, h, c);
        break;
    case Boxtype.shadowBox:
        flShadowBox(x, y, w, h, c);
        break;
    case Boxtype.borderFrame:
        flBorderFrame(x, y, w, h, c);
        break;
    case Boxtype.shadowFrame:
        flShadowFrame(x, y, w, h, c);
        break;
    case Boxtype.roundUpBox:
        flRoundUpBox(x, y, w, h, c);
        break;
    case Boxtype.roundDownBox:
        flRoundDownBox(x, y, w, h, c);
        break;
    case Boxtype.diamondUpBox:
        flDiamondUpBox(x, y, w, h, c);
        break;
    case Boxtype.diamondDownBox:
        flDiamondDownBox(x, y, w, h, c);
        break;
    case Boxtype.ovalBox:
        flOvalBox(x, y, w, h, c);
        break;
    case Boxtype.oshadowBox:
        flOvalShadowBox(x, y, w, h, c);
        break;
    case Boxtype.ovalFrame:
        flOvalFrame(x, y, w, h, c);
        break;
    case Boxtype.oflatBox:
        flOvalFlatBox(x, y, w, h, c);
        break;
    case Boxtype.roundedBox:
        flRoundedBox(x, y, w, h, c);
        break;
    case Boxtype.rshadowBox:
        flRshadowBox(x, y, w, h, c);
        break;
    case Boxtype.roundedFrame:
        flRoundedFrame(x, y, w, h, c);
        break;
    case Boxtype.rflatBox:
        flRflatBox(x, y, w, h, c);
        break;
    case Boxtype.gleamUpBox:
        flGleamUpBox(x, y, w, h, c);
        break;
    case Boxtype.gleamDownBox:
        flGleamDownBox(x, y, w, h, c);
        break;
    case Boxtype.gleamUpFrame:
        flGleamUpFrame(x, y, w, h, c);
        break;
    case Boxtype.gleamDownFrame:
        flGleamDownFrame(x, y, w, h, c);
        break;
    case Boxtype.gleamThinUpBox:
        flGleamThinUpBox(x, y, w, h, c);
        break;
    case Boxtype.gleamThinDownBox:
        flGleamThinDownBox(x, y, w, h, c);
        break;
    case Boxtype.gleamRoundUpBox:
        // No distinct round shape FLTK either -- see this section's
        // own module comment (above gleamColor()) for why.
        flGleamUpBox(x, y, w, h, c);
        break;
    case Boxtype.gleamRoundDownBox:
        flGleamDownBox(x, y, w, h, c);
        break;
    case Boxtype.gtkUpBox:
        flGtkUpBox(x, y, w, h, c);
        break;
    case Boxtype.gtkDownBox:
        flGtkDownBox(x, y, w, h, c);
        break;
    case Boxtype.gtkUpFrame:
        flGtkUpFrame(x, y, w, h, c);
        break;
    case Boxtype.gtkDownFrame:
        flGtkDownFrame(x, y, w, h, c);
        break;
    case Boxtype.gtkThinUpBox:
        flGtkThinUpBox(x, y, w, h, c);
        break;
    case Boxtype.gtkThinDownBox:
        flGtkThinDownBox(x, y, w, h, c);
        break;
    case Boxtype.gtkThinUpFrame:
        flGtkThinUpFrame(x, y, w, h, c);
        break;
    case Boxtype.gtkThinDownFrame:
        flGtkThinDownFrame(x, y, w, h, c);
        break;
    case Boxtype.gtkRoundUpBox:
        flGtkRoundUpBox(x, y, w, h, c);
        break;
    case Boxtype.gtkRoundDownBox:
        flGtkRoundDownBox(x, y, w, h, c);
        break;
    case Boxtype.oxyUpBox:
        flOxyUpBox(x, y, w, h, c);
        break;
    case Boxtype.oxyDownBox:
        flOxyDownBox(x, y, w, h, c);
        break;
    case Boxtype.oxyUpFrame:
        flOxyUpFrame(x, y, w, h, c);
        break;
    case Boxtype.oxyDownFrame:
        flOxyDownFrame(x, y, w, h, c);
        break;
    case Boxtype.oxyThinUpBox:
        flOxyThinUpBox(x, y, w, h, c);
        break;
    case Boxtype.oxyThinDownBox:
        flOxyThinDownBox(x, y, w, h, c);
        break;
    case Boxtype.oxyThinUpFrame:
        flOxyThinUpFrame(x, y, w, h, c);
        break;
    case Boxtype.oxyThinDownFrame:
        flOxyThinDownFrame(x, y, w, h, c);
        break;
    case Boxtype.oxyRoundUpBox:
        flOxyRoundUpBox(x, y, w, h, c);
        break;
    case Boxtype.oxyRoundDownBox:
        flOxyRoundDownBox(x, y, w, h, c);
        break;
    case Boxtype.oxyButtonUpBox:
        flOxyButtonUpBox(x, y, w, h, c);
        break;
    case Boxtype.oxyButtonDownBox:
        flOxyButtonDownBox(x, y, w, h, c);
        break;
    case Boxtype.plasticUpBox:
        flPlasticUpBox(x, y, w, h, c);
        break;
    case Boxtype.plasticDownBox:
        flPlasticDownBox(x, y, w, h, c);
        break;
    case Boxtype.plasticUpFrame:
        flPlasticUpFrame(x, y, w, h, c);
        break;
    case Boxtype.plasticDownFrame:
        flPlasticDownFrame(x, y, w, h, c);
        break;
    case Boxtype.plasticThinUpBox:
        flPlasticThinUpBox(x, y, w, h, c);
        break;
    case Boxtype.plasticThinDownBox:
        // No distinct "thin down" variant FLTK either --
        // fl_plastic.cxx never defines fl_plastic_thin_down_box at
        // all; fl_box_table's own _FL_PLASTIC_THIN_DOWN_BOX row points
        // at the plain fl_plastic_down_box, ported faithfully as-is.
        flPlasticDownBox(x, y, w, h, c);
        break;
    case Boxtype.plasticRoundUpBox:
        flPlasticUpRound(x, y, w, h, c);
        break;
    case Boxtype.plasticRoundDownBox:
        flPlasticDownRound(x, y, w, h, c);
        break;
    default:
        // Every boxtype fl.core.boxTable has metrics for is now
        // drawable -- all four scheme families (rounded/gleam/gtk+/
        // oxy/plastic) are handled above. This default: only exists
        // for forward-compat with any future boxtype this switch
        // hasn't been extended for yet.
        break;
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================
//
// Everything that actually touches Xlib/Xft needs a live X display
// (display_/gc_/drawable_/xftDraw_ are only set by
// fl.platform_x11.initGraphics()/setDrawable(), see the module
// comment) -- `dub test` must stay headless-safe, so none of that is
// exercised here. What *is* tested: fl_color()'s save/restore idiom
// (pure bookkeeping, guards on `gc_ !is null`), and the text
// primitives' documented headless fallback behavior (xftFontFor()
// returns/caches null when display_ is null, and every caller of
// currentXftFont_ has a placeholder for exactly that case).

unittest
{
    // fl_color()/fl_color(c) round-trip -- the `auto old = fl_color();
    // ...; fl_color(old);` save/restore idiom used throughout
    // FLTK's example/test programs. Doesn't assert on the starting
    // value: currentColor_ is process-wide module state, and other
    // modules' unittests that call draw() (fl.slider/fl.roller/
    // fl.light_button/...) run in an unspecified order relative to
    // this one and leave their own last fl_color() call behind.
    fl_color(white);
    assert(fl_color() == white);

    Color old = fl_color();
    fl_color(black);
    assert(fl_color() == black);
    fl_color(old);
    assert(fl_color() == white);
}

unittest
{
    // Headless (no display_): fl_font() resolves to a cached null
    // XftFont, and every metric function falls back to its documented
    // placeholder instead of dereferencing it.
    //
    // Force that precondition explicitly rather than assuming it -- see
    // resetForTest()'s own doc comment for why it's needed here.
    resetForTest();

    fl_font(helvetica, 14);
    assert(width("hello", 5) == 5 * 6.0); // 6px/byte placeholder
    assert(width("hello") == 5 * 6.0);
    assert(height(helvetica, 14) == 14 + 4); // "size + 4" placeholder
    assert(height() == 14 + 4);
    assert(descent() == 4);
}

unittest
{
    // fl_measure() composes width()/height() per '\n'-separated
    // line -- headless-safe since both fall back to placeholders (see
    // the unittest above), so the arithmetic is exactly checkable.
    fl_font(helvetica, 14);
    int w, h;

    fl_measure("", w, h);
    assert(w == 0 && h == 0);

    fl_measure("hello", w, h);
    assert(w == cast(int)(5 * 6.0 + 0.5) && h == (14 + 4));

    fl_measure("hi\nworld!", w, h); // widest line ("world!", 6 bytes) wins; 2 lines
    assert(w == cast(int)(6 * 6.0 + 0.5) && h == 2 * (14 + 4));
}

unittest
{
    // wrapLine(): headless-safe, same 6px/byte placeholder as above --
    // "hello"/"world" are 5 bytes (30px) each, "foo" is 3 (18px).
    fl_font(helvetica, 14);

    // maxWidth <= 0 disables wrapping entirely.
    assert(wrapLine("hello world foo", 0) == ["hello world foo"]);

    // 30px alone fits under 40, but any two words together (66px/54px)
    // don't -- one word per resulting line.
    assert(wrapLine("hello world foo", 40) == ["hello", "world", "foo"]);

    // Never split mid-word: a single word wider than maxWidth is still
    // emitted whole on its own line.
    assert(wrapLine("aaaaaaaaaa", 10) == ["aaaaaaaaaa"]);

    // Wide enough for everything on one line.
    assert(wrapLine("hello world foo", 200) == ["hello world foo"]);

    assert(wrapLine("", 40) == [""]);
}

unittest
{
    // fl_measure()'s in/out wrap-width parameter: presetting w wraps
    // "hello world foo" the same way the wrapLine() unittest above
    // does (2 words/line fit under 40px only when they're this short),
    // reporting the widest *wrapped* line and height for every
    // resulting line, not just '\n'-separated ones.
    fl_font(helvetica, 14);
    int w = 40, h;
    fl_measure("hello world foo", w, h);
    assert(w == 5 * 6); // "hello"/"world" both 30px; "foo" narrower
    assert(h == 3 * (14 + 4)); // 3 wrapped lines

    // w == 0 on input keeps the old unwrapped behavior.
    w = 0;
    fl_measure("hello world foo", w, h);
    assert(w == cast(int)("hello world foo".length * 6.0 + 0.5));
    assert(h == 14 + 4);
}

unittest
{
    // fl_draw()'s image-aware overload: headless (no display_), so
    // every glyph/image draw call along the way is a documented no-op
    // -- what this actually exercises is that a null image reduces to
    // exactly the plain text-only overload (the two are one
    // implementation, see that overload's own doc comment),
    // and that passing a real Image plus every alignment combination
    // this overload branches on doesn't crash headlessly (RGBImage
    // itself has no display to draw into either, so its own draw()
    // early-returns the same way fl_draw()'s text path does).
    import fl.image : RGBImage;

    fl_font(helvetica, 14);
    fl_draw("hello", 0, 0, 100, 20, alignCenter); // the plain forward, still works
    fl_draw("", 0, 0, 100, 20, alignCenter, null); // no text, no image: no-op, no crash
    fl_draw("hello", 5, 5); // plain baseline-positioned form, headless no-op
    fl_draw("", 5, 5); // empty string: no-op, no crash

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto img = new RGBImage(bits, 2, 2, 3);

    fl_draw("hello", 0, 0, 100, 20, alignCenter, img); // image above/below text (default)
    fl_draw("hello", 0, 0, 100, 20, cast(Align)(alignCenter | alignImageNextToText), img);
    fl_draw("hello", 0, 0, 100, 20,
        cast(Align)(alignCenter | alignImageNextToText | alignTextOverImage), img, 4);
    fl_draw("hello", 0, 0, 100, 20, cast(Align)(alignCenter | alignTextOverImage), img);
    fl_draw("", 0, 0, 100, 20, alignCenter, img); // image only, no text
    fl_draw("hello", 0, 0, 100, 20, cast(Align)(alignCenter | alignImageBackdrop), img); // ignored here
}

unittest
{
    // rgbColor(): packs r,g,b into a "free" (packed-RGB) Color,
    // except pure black special-cases to the compact `black` index
    // (matching FLTK's rgbColor() inline) -- pure, no display
    // needed, safe headless.
    assert(rgbColor(0, 0, 0) == black);

    ubyte r, g, b;
    colorToRgb8(rgbColor(200, 100, 50), r, g, b);
    assert(r == 200 && g == 100 && b == 50);
}

unittest
{
    // colorAverage(): weight 1.0 is "all c1", weight 0.0 is "all
    // c2" -- both exact (no float-rounding ambiguity at a fractional
    // weight), so a solid way to pin down which input the weight favors.
    ubyte r, g, b;

    colorToRgb8(colorAverage(white, black, 1.0f), r, g, b);
    assert(r == 255 && g == 255 && b == 255);

    colorToRgb8(colorAverage(white, black, 0.0f), r, g, b);
    assert(r == 0 && g == 0 && b == 0);
}

unittest
{
    // inactive(): dims c 33% of the way toward FL_GRAY (0xc0c0c0).
    // white dims toward gray but never reaches it, and gray/white are
    // both neutral so the result stays neutral (r==g==b).
    ubyte r, g, b;
    colorToRgb8(inactive(white), r, g, b);
    assert(r > 0xc0 && r < 255);
    assert(r == g && g == b);
}

unittest
{
    // contrast(): a color that already contrasts strongly against
    // the background is returned unchanged; insufficient contrast
    // (including fg == bg) substitutes plain black or white instead.
    assert(contrast(black, white) == black); // already legible
    assert(contrast(white, black) == white); // already legible

    Color c = contrast(gray, gray); // zero contrast -> always substituted
    assert(c == black || c == white);
    assert(c != gray);
}

unittest
{
    // contrast() (CIELAB) vs. contrastLegacy(): the exact real-
    // world case that surfaced this divergence -- source/examples/
    // tabs_simple.d's "Button A1" (fl.enumerations.colorTable[89] ==
    // 0xff240000, RGB (255,36,0), a red-orange) against a black focus-
    // rectangle foreground. The two algorithms genuinely disagree
    // here: legacy's simple weighted-RGB luminance puts this color
    // just under its "sufficient contrast" threshold and falls back to
    // white; CIELAB's perceptual lightness calculation finds black
    // already contrasts enough, so it's returned unchanged. Confirmed
    // by hand (see the session that added this) before writing this
    // test, not just asserted after the fact.
    // Plain color-table index, matching `b1.color(89)` in the real
    // sample exactly -- colorToRgb8() resolves it via colorTable[89]
    // internally (0xff240000, RGB (255,36,0)), same as fl_color()
    // would for a widget actually drawn with this background.
    Color bg = cast(Color) 89;
    assert(contrastLegacy(black, bg) == white);
    assert(contrast(black, bg) == black);
}

unittest
{
    // luminance()/lightness(): pure sanity checks against their
    // own documented ranges and monotonicity -- black/white are the
    // fixed endpoints in both scales. Epsilon-compared, not exact --
    // FLTK's own three luminance weights (0.2126729/0.7151522/
    // 0.0721750) don't sum to exactly 1.0 in decimal, so even
    // pow(1.0, 2.4) == 1.0 exactly per channel leaves a tiny residual.
    import std.math : abs;

    assert(luminance(black) == 0.0);
    assert(abs(luminance(white) - 1.0) < 1e-6);
    assert(lightness(black) == 0.0);
    // white: Y=1.0 > 216/24389, so pow(1,1/3)*116-16 == 100 exactly.
    assert(abs(lightness(white) - 100.0) < 1e-4);

    // Monotonicity: a lighter gray has both higher luminance and
    // higher lightness than a darker one.
    assert(luminance(gray) > luminance(black));
    assert(lightness(gray) > lightness(black));
    assert(lightness(gray) < lightness(white));
}

// The clip-stack bookkeeping (pushClip()/popClip()/notClipped()/
// clipBox()) is pure arithmetic -- see this module's "Clipping"
// section comment for why a plain rectangle stack is exactly as
// capable as FLTK's general Fl_Region here -- so it's fully
// testable headless. clipStack_ is reset at the start of each test
// (rather than assumed empty) since it's process-wide module state;
// other modules' widget unittests that call draw() (fl.pack/
// fl.progress, both of which push/pop a clip internally) run in an
// unspecified order relative to these.

unittest
{
    // No active clip: notClipped() is always true, clipBox() reports
    // "unclipped" and echoes the input back unchanged.
    clipStack_ = [];

    assert(notClipped(0, 0, 10, 10));
    assert(notClipped(-1000, -1000, 1, 1));

    int X, Y, W, H;
    assert(clipBox(5, 6, 7, 8, X, Y, W, H) == false);
    assert(X == 5 && Y == 6 && W == 7 && H == 8);
}

unittest
{
    // A single active clip: notClipped() is true for anything
    // overlapping it (even partially), false for anything entirely
    // outside it; clipBox() intersects and reports "clipped" whenever
    // the result differs from the input.
    clipStack_ = [];

    pushClip(10, 10, 100, 100); // clip = [10,10]..[110,110]

    assert(notClipped(10, 10, 100, 100)); // exact match
    assert(notClipped(0, 0, 20, 20));     // partial overlap (top-left corner)
    assert(notClipped(105, 105, 50, 50)); // partial overlap (bottom-right corner)
    assert(!notClipped(200, 200, 10, 10)); // entirely outside
    assert(!notClipped(0, 0, 5, 5));       // entirely outside (above/left)

    int X, Y, W, H;
    assert(clipBox(10, 10, 100, 100, X, Y, W, H) == false); // already inside: unchanged
    assert(X == 10 && Y == 10 && W == 100 && H == 100);

    assert(clipBox(0, 0, 20, 20, X, Y, W, H) == true); // clipped to the overlap
    assert(X == 10 && Y == 10 && W == 10 && H == 10);

    assert(clipBox(200, 200, 10, 10, X, Y, W, H) == true); // entirely outside
    assert(W == 0 && H == 0);

    popClip();
    assert(notClipped(200, 200, 10, 10)); // clip lifted
    assert(clipStack_.length == 0);
}

unittest
{
    // Nested pushClip() intersects with whatever's already active,
    // never widens it.
    clipStack_ = [];

    pushClip(0, 0, 100, 100);
    pushClip(50, 50, 100, 100); // intersect -> [50,50]..[100,100]

    assert(notClipped(60, 60, 5, 5));       // inside the intersection
    assert(!notClipped(10, 10, 5, 5));      // inside the outer push, but outside the inner
    assert(!notClipped(150, 150, 5, 5));    // outside both

    popClip();
    assert(notClipped(10, 10, 5, 5)); // back to just the outer push
    popClip();
    assert(notClipped(150, 150, 5, 5)); // no clip at all
    assert(clipStack_.length == 0);
}

unittest
{
    // A degenerate pushClip() (w <= 0 or h <= 0) clips everything away
    // -- FLTK's "make empty clip region" case -- rather than being
    // treated as "no clip".
    clipStack_ = [];

    pushClip(10, 10, 0, 0);
    assert(!notClipped(10, 10, 1, 1));
    assert(!notClipped(0, 0, 1000, 1000));
    popClip();

    assert(notClipped(10, 10, 1, 1)); // lifted
    assert(clipStack_.length == 0);
}

unittest
{
    // computeCheckPoints(): pure geometry, safe headless -- golden
    // values cross-checked against a standalone re-implementation of
    // FLTK's drawCheck() size-fitting arithmetic.
    auto p = computeCheckPoints(Rect(0, 0, 20, 20));
    assert(p.x0 == 1 && p.y0 == 8);
    assert(p.x1 == 7 && p.y1 == 14);
    assert(p.x2 == 19 && p.y2 == 2);
    assert(p.x3 == 19 && p.y3 == 5);
    assert(p.x4 == 7 && p.y4 == 17);
    assert(p.x5 == 1 && p.y5 == 11);

    // A smaller box exercises the d1 > md clamp differently (d1 stays
    // below the max-size clamp here, unlike the 20x20 case above).
    auto q = computeCheckPoints(Rect(0, 0, 12, 12));
    assert(q.x0 == 1 && q.y0 == 4);
    assert(q.x1 == 4 && q.y1 == 7);
    assert(q.x2 == 10 && q.y2 == 1);
    assert(q.x3 == 10 && q.y3 == 4);
    assert(q.x4 == 4 && q.y4 == 10);
    assert(q.x5 == 1 && q.y5 == 7);
}

unittest
{
    // arrowSize(): pure geometry, safe headless. A square 20x20 box
    // gives the same size regardless of pointing axis (both d1 and d2
    // land at 9, clamped to the [2,6] ceiling -> 6).
    assert(arrowSize(Rect(0, 0, 20, 20), Orientation.orientLeft) == 6);
    assert(arrowSize(Rect(0, 0, 20, 20), Orientation.orientUp) == 6);

    // A box too small to reach the clamp falls through to the raw
    // min(d1, d2) instead -- 8x8: d1 = (8-2)/1 = 6, d2 = (8-2)/2 = 3,
    // so the cross-axis half-size (3) wins, still within [2,6].
    assert(arrowSize(Rect(0, 0, 8, 8), Orientation.orientLeft) == 3);

    // The floor clamp: a box so small the raw size would drop below 2.
    assert(arrowSize(Rect(0, 0, 4, 4), Orientation.orientLeft) == 2);

    // fl_draw_arrow_double()'s num=2 halves the along-axis term (d1)
    // before the min/clamp -- a 10x20 box makes the difference visible:
    // at num=1, d1 = (10-2)/1 = 8 and d2 = (20-2)/2 = 9, so d1 wins and
    // clamps to 6; at num=2, d1 drops to (10-2)/2 = 4, which now wins
    // outright (no clamp needed), confirming num actually divides d1
    // rather than being ignored.
    assert(arrowSize(Rect(0, 0, 10, 20), Orientation.orientLeft, 1) == 6);
    assert(arrowSize(Rect(0, 0, 10, 20), Orientation.orientLeft, 2) == 4);
}

unittest
{
    // stripShortcutMarker(): pure string manipulation, safe headless.
    ptrdiff_t at;

    // A no-op when fl_draw_shortcut isn't set, matching FLTK's own
    // gate -- '&' passes through untouched.
    fl_draw_shortcut = 0;
    assert(stripShortcutMarker("&Save", at) == "&Save");
    assert(at == -1);

    fl_draw_shortcut = 1;
    scope(exit) fl_draw_shortcut = 0;

    // No marker at all: unchanged, no underline.
    assert(stripShortcutMarker("Save", at) == "Save");
    assert(at == -1);

    // "&Save" -> "Save", underline before 'S' (offset 0).
    assert(stripShortcutMarker("&Save", at) == "Save");
    assert(at == 0);

    // Marker mid-string: "Sa&ve" -> "Save", underline before 'v' (offset 2).
    assert(stripShortcutMarker("Sa&ve", at) == "Save");
    assert(at == 2);

    // "&&" is an escaped literal '&', not a marker.
    assert(stripShortcutMarker("Save && Load", at) == "Save & Load");
    assert(at == -1);

    // A mix: literal "&&" plus a real marker later in the same line.
    assert(stripShortcutMarker("A && &B", at) == "A & B");
    assert(at == 4); // "A & " is 4 bytes, underline lands before 'B'

    // A trailing lone '&' (no following character) is left as-is,
    // matching FLTK's `*(p+1)` guard.
    assert(stripShortcutMarker("Save&", at) == "Save&");
    assert(at == -1);

    // Mode 2 (fl.choice's "hack value to make '&' disappear"): still
    // strips the marker, but never records an underline position.
    fl_draw_shortcut = 2;
    assert(stripShortcutMarker("&Save", at) == "Save");
    assert(at == -1);
    assert(stripShortcutMarker("Sa&ve", at) == "Save");
    assert(at == -1);
    assert(stripShortcutMarker("Save && Load", at) == "Save & Load"); // "&&" unaffected
    assert(at == -1);
}

unittest
{
    // plasticColorAverage()/currentPlasticAverage(): pure clamping
    // logic, safe headless (no display needed -- this is just the
    // [10,100] percent -> [0.1,1.0] float conversion, not any actual
    // color drawing).
    scope(exit) plasticAverage_ = -1.0f; // don't leak into other tests

    plasticColorAverage(50);
    assert(currentPlasticAverage() == 0.5f);

    // Below the documented minimum: clamps to 10%.
    plasticColorAverage(0);
    assert(currentPlasticAverage() == 0.10f);

    // Above the documented maximum: clamps to 100%.
    plasticColorAverage(500);
    assert(currentPlasticAverage() == 1.0f);

    // Exact boundaries pass through unclamped.
    plasticColorAverage(10);
    assert(currentPlasticAverage() == 0.10f);
    plasticColorAverage(100);
    assert(currentPlasticAverage() == 1.0f);
}

unittest
{
    // grayRampChar()/shadeColor(): pure value composition, safe
    // headless -- shadeColor() calls colorAverage(), which is
    // itself pure arithmetic (no display needed), same as this
    // module's other colorAverage()-based unit tests elsewhere.
    plasticColorAverage(100); // weight 1.0 -> shadeColor() returns the ramp color unchanged
    scope(exit) plasticAverage_ = -1.0f;

    assert(grayRampChar('A') == gray0);
    assert(grayRampChar('B') == gray0 + 1);
    assert(shadeColor('A', white) == colorAverage(grayRampChar('A'), white, 1.0f));
}

// ---------------------------------------------------------------------
// Image drawing (backs fl.image's RGBImage.draw()/fl.bitmap's
// Bitmap.draw()) -- fl.image's Milestone 1. Ported from
// fl_draw_image()/Fl_Xlib_Graphics_Driver::draw_image_unscaled()
// (src/drivers/Xlib/Fl_Xlib_Graphics_Driver_image.cxx) and
// Fl_Xlib_Graphics_Driver::draw_fixed(Fl_Bitmap*,...)/create_bitmask(),
// radically simplified in the same direction this whole module already
// takes: FLTK supports every X11 visual depth (8/16/24/32bpp),
// byte order, and colormap/PseudoColor palette via a table of ~15
// per-format pixel converters plus 8-bit error-diffusion dithering;
// this port assumes a TrueColor/DirectColor visual everywhere (see
// fl_color()'s own doc comment), but not a *fixed* 8-8-8-in-32bpp
// layout: drawImage() packs each
// pixel via xpixel(r,g,b) -- the same mask/shift state
// figureOutVisual() derives from the active visual's real red/green/
// blue masks -- into a ZPixmap sized for that visual's actual
// bits-per-pixel (visualBitsPerPixel_/visualDepth_, queried from
// XListPixmapFormats()), querying only the client-side byte order
// (XImageByteOrder()) to know which byte each channel lands in. For
// today's real default visual this produces byte-identical output to
// the old hardcoded formula. Still no colormap/PseudoColor fallback
// (figureOutVisual() falls back to the old fixed 8-8-8 layout for a
// non-TrueColor visual instead, see that function's own doc comment),
// no negative d/l (FLTK's horizontal/vertical image-flip feature)
// -- no caller in this port needs either.
//
// No offscreen-Pixmap image cache exists either (FLTK's own
// cache()/id_/Fl_Image_Surface machinery) -- every draw() call
// re-converts and re-blits directly to the window, matching this
// port's drawing model everywhere else (fl_rectf()/fl_line()/etc. all
// draw directly too, no caching layer exists anywhere in this port).
// Slower than FLTK's cached-Pixmap approach on repeated redraws of
// the same image, but correct, and consistent with not having the
// Fl_Image_Surface off-screen-rendering-surface abstraction this would
// need to build on top of (the same "Deferred" family that blocks
// Fl_Double_Window's real double-buffering too -- see that row).
//
// Alpha (d==2/4) compositing is real: fl.pixmap's transparency is a
// 1-bit clip
// mask, never blended alpha (see that module's own row) -- the actual
// live consumer is fl.ico_image, whose real .ico files commonly carry
// genuine anti-aliased alpha edges that need real compositing rather
// than rendering as solid
// squared-off blocks. Ported from Fl_Xlib_Graphics_Driver's own
// `alpha_blend()` (src/drivers/Xlib/Fl_Xlib_Graphics_Driver_image.cxx)
// -- this port's non-XRender fallback path, since no XRender binding
// exists here either (`fl_can_do_alpha_blending()` is always
// FLTK's own "false" case as far as this port is concerned): reads
// the destination rectangle back via the already-real
// readPixelsFromDrawable(), blends source-over-dest per pixel
// (srca==255 "copy", srca==0 "ignore dest", else a premultiplied
// blend -- same three-way special case FLTK's own loop uses, for
// the same reason: exact edge behavior at full/zero alpha shouldn't
// depend on float rounding), and draws the blended result back as
// plain opaque RGB. Falls back to the previous always-opaque behavior
// if the destination read fails (matching FLTK's own `if (!dst) {
// drawImage(...); return; }` graceful-degradation exactly -- the
// same window-not-yet-viewable hazard readImage()'s own doc
// comment already documents applies here too, since this reuses that
// exact primitive).

version (linux)
{
    /// Shared packing loop behind `drawImage()`/`drawImageMono()`
    /// (raw-buffer forms): converts `w`*`h` pixels of `d`-byte-stride
    /// source data into a `ZPixmap` buffer laid out for the *active*
    /// visual's real depth/bits-per-pixel (`visualBitsPerPixel_`, see
    /// `figureOutVisual()`) via `fl_xpixel(r,g,b)`,
    /// the same mask/shift-based pixel value `fl_color()` itself
    /// uses (see that function's own doc comment). For today's real
    /// default 24-bit-in-32bpp TrueColor visual this produces
    /// byte-identical output to the old hardcoded formula. `mono` forces
    /// every pixel to the gray value `src[0]` regardless of `d`,
    /// matching FLTK's `fl_draw_image_mono()` (which uses only the
    /// first byte of each `d`-byte pixel as a luminance sample, ignoring
    /// the rest) -- distinct from plain `drawImage()`'s own
    /// `d == 1 || d == 2` gray case, which only kicks in for *narrow*
    /// pixel strides.
    private ubyte[] packImageBuffer(const(ubyte)* buf, int w, int h, int d, int l, bool mono)
    {
        // A negative `d` is the documented horizontal-flip form (see
        // drawImage()'s own doc comment): the pixel pointer steps left
        // by `d`, but the pixel's own bytes are still read forward, and
        // every *size* (the default row stride, the gray-vs-color
        // classification) is computed from |d| -- matching FLTK's
        // own `innards()` (`if (!linedelta) linedelta = W*abs(delta);`)
        // and its converters' `mono = (d>-3 && d<3)` test.
        immutable int ad = d < 0 ? -d : d;
        int lineDelta = l ? l : w * ad;
        int byteOrder = XImageByteOrder(display_);
        int bytesPerPixel = visualBitsPerPixel_ / 8;
        auto packed = new ubyte[w * h * bytesPerPixel];
        size_t idx = 0;
        for (int row = 0; row < h; row++)
        {
            const(ubyte)* src = buf + row * lineDelta;
            for (int col = 0; col < w; col++)
            {
                ubyte r, g, b;
                if (mono || ad == 1 || ad == 2) r = g = b = src[0];
                else { r = src[0]; g = src[1]; b = src[2]; }
                c_ulong pixel = xpixel(r, g, b);
                final switch (bytesPerPixel)
                {
                case 4:
                    if (byteOrder == MSBFirst)
                    {
                        packed[idx++] = cast(ubyte)(pixel >> 24);
                        packed[idx++] = cast(ubyte)(pixel >> 16);
                        packed[idx++] = cast(ubyte)(pixel >> 8);
                        packed[idx++] = cast(ubyte) pixel;
                    }
                    else
                    {
                        packed[idx++] = cast(ubyte) pixel;
                        packed[idx++] = cast(ubyte)(pixel >> 8);
                        packed[idx++] = cast(ubyte)(pixel >> 16);
                        packed[idx++] = cast(ubyte)(pixel >> 24);
                    }
                    break;
                case 3:
                    if (byteOrder == MSBFirst)
                    {
                        packed[idx++] = cast(ubyte)(pixel >> 16);
                        packed[idx++] = cast(ubyte)(pixel >> 8);
                        packed[idx++] = cast(ubyte) pixel;
                    }
                    else
                    {
                        packed[idx++] = cast(ubyte) pixel;
                        packed[idx++] = cast(ubyte)(pixel >> 8);
                        packed[idx++] = cast(ubyte)(pixel >> 16);
                    }
                    break;
                case 2:
                    ushort p16 = cast(ushort) pixel;
                    if (byteOrder == MSBFirst)
                    {
                        packed[idx++] = cast(ubyte)(p16 >> 8);
                        packed[idx++] = cast(ubyte) p16;
                    }
                    else
                    {
                        packed[idx++] = cast(ubyte) p16;
                        packed[idx++] = cast(ubyte)(p16 >> 8);
                    }
                    break;
                case 1:
                    packed[idx++] = cast(ubyte) pixel;
                    break;
                }
                src += d;
            }
        }
        return packed;
    }

    /// Blits a buffer already packed by `packImageBuffer()` onto the
    /// current drawable via `XPutImage()` -- the second half of both
    /// raw-buffer image-drawing entry points below. Uses the active
    /// visual's real depth/bits-per-pixel (`visualDepth_`/
    /// `visualBitsPerPixel_`), matching `packImageBuffer()`'s own
    /// layout.
    private void putPackedImage(ubyte[] packed, int x, int y, int w, int h)
    {
        int byteOrder = XImageByteOrder(display_);
        XImage xi;
        xi.width = w;
        xi.height = h;
        xi.format = ZPixmap;
        xi.data = cast(char*) packed.ptr;
        xi.byte_order = byteOrder;
        xi.bitmap_unit = 32;
        xi.bitmap_bit_order = byteOrder;
        xi.bitmap_pad = 32;
        xi.depth = visualDepth_;
        xi.bytes_per_line = w * (visualBitsPerPixel_ / 8);
        xi.bits_per_pixel = visualBitsPerPixel_;
        XPutImage(display_, drawable_, gc_, &xi, 0, 0, x + offsetX_, y + offsetY_, cast(uint) w, cast(uint) h);
    }

    /**
     * Draws an 8-bit-per-channel image directly to the current
     * drawable. buf points at the top-left pixel; d is 1 (gray), 2
     * (gray+alpha, real per-pixel compositing -- see this section's
     * own top comment and alphaBlendImage()'s doc comment), 3 (RGB),
     * or 4 (RGBA, ditto); l is the byte stride between rows (0 means
     * w*|d|).
     *
     * Both deltas may be **negative**, exactly as FLTK's own
     * `fl_draw_image()` documents (and `test/unittest_images.cxx`'s
     * FLIPH/LX controls exercise): a negative `l` flips the image
     * vertically (`buf` points at the *last* row, row arithmetic walks
     * up), and a negative `d` flips it horizontally (`buf` points at
     * the first byte of the *last* pixel of its first row, the pixel
     * pointer steps left by `d`, and each pixel's own `|d|` bytes are
     * still read forward). Everything that *sizes* something --
     * `l`'s `w*|d|` default, the gray-vs-color classification
     * (FLTK's own `mono = (d>-3 && d<3)`), the alpha gate below --
     * uses `|d|`; only the pointer step itself is signed. Matches
     * FLTK's `innards()` (`src/drivers/Xlib/
     * Fl_Xlib_Graphics_Driver_image.cxx`) exactly.
     *
     * `(x,y,w,h)` are FLTK units, scaled the same
     * `scaledFloor(x+w)-scaledFloor(x)` edge-alignment way `fl_rectf()`
     * does -- at `currentScale() == 1`
     * this is a no-op (`sw == w && sh == h`), so the resample path never
     * runs. Otherwise `buf` is resampled to the scaled size first (see
     * `resampleImageNearest()`), and the *scaled* buffer/geometry is
     * what `alphaBlendImage()`/`putPackedImage()` below actually see --
     * neither of those two needed any scale-awareness of their own as a
     * result.
     */
    void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d = 3, int l = 0)
    {
        if (w <= 0 || h <= 0 || buf is null) return;
        if (currentDriver !is null)
        {
            currentDriver.drawImage(buf, x, y, w, h, d, l);
            return;
        }
        if (gc_ is null) return;

        int sx = scaledFloor(x), sy = scaledFloor(y);
        int sw = scaledFloor(x + w) - sx, sh = scaledFloor(y + h) - sy;
        if (sw <= 0 || sh <= 0) return;

        immutable int ad = d < 0 ? -d : d;
        const(ubyte)* drawBuf = buf;
        int drawW = w, drawH = h, drawL = l, drawD = d;
        ubyte[] resampled;
        if (sw != w || sh != h)
        {
            resampled = resampleImageNearest(buf, w, h, d, l, sw, sh);
            drawBuf = resampled.ptr;
            drawW = sw;
            drawH = sh;
            drawL = sw * ad;
            // The resampled buffer is always normal-order, positively
            // strided -- a negative `d`'s flip is already baked into it,
            // so everything downstream must use |d| or it would flip a
            // second time (and misclassify gray vs. color besides).
            drawD = ad;
        }

        if (ad == 2 || ad == 4)
        {
            if (alphaBlendImage(drawBuf, sx, sy, drawW, drawH, drawD, drawL)) return;
            // Destination read failed (e.g. window not yet viewable --
            // see alphaBlendImage()'s own doc comment) -- fall through
            // to the previous always-opaque behavior rather than
            // drawing nothing at all, matching FLTK's own
            // graceful-degradation exactly.
        }
        putPackedImage(packImageBuffer(drawBuf, drawW, drawH, drawD, drawL, false), sx, sy, drawW, drawH);
    }

    /**
     * Draws an image buffer that has *already* been resampled to its
     * correct on-screen pixel size -- the full-color counterpart of
     * `drawBitmapFixed()`, same split of responsibility: only the
     * *position* (`x,y`) is converted from FLTK units to device pixels
     * here (via `scaledFloor()`, same as every other primitive);
     * `drawW`/`drawH`/`drawL` describe `buf`'s own real pixel
     * dimensions and are used exactly as given, with no further
     * resampling.
     *
     * This exists because `drawImage()` above conflates two different
     * things into one `(w,h)` pair: "the size to interpret `buf` at"
     * and "the FLTK-unit box to scale `buf` up/down to fit" -- correct
     * only when a caller hands over an *unscaled*, native-resolution
     * buffer and wants `drawImage()` itself to do the one-and-only
     * device-scale resample. `fl.pixmap.Pixmap.draw()`/`fl.image.
     * RGBImage.draw()` both now do their *own* scale-aware resampling
     * first (mirroring `fl.bitmap.Bitmap.draw()`'s established
     * `cachedW_`/`cachedH_` precedent, and FLTK's `Fl_Graphics_
     * Driver::cache_size()` + `pxm->copy(w2,h2)`/`img->copy(w2,h2)`),
     * producing a buffer already at the exact target device-pixel
     * size -- handing *that* to plain `drawImage()` would silently
     * resample it a second time on top (this module's own documented
     * nearest-neighbor approximation, applied
     * twice): an icon's
     * logical-vs-native-resolution headroom (e.g. a 32x32 XPM drawn at
     * 16 logical units, matching a 200% scale exactly) would get downscaled
     * to the logical size *first*, throwing away the native detail,
     * then blown back up nearest-neighbor from that degraded
     * intermediate -- instead of FLTK's single exact-size copy.
     * `drawImageFixed()` avoids this: callers that have already resolved
     * their own buffer to the right resolution use this instead of
     * `drawImage()`, so the size conversion only ever happens once.
     *
     * The `currentDriver !is null` branch below calls
     * `currentDriver.drawImageFixed()`, not `.drawImage()`: the same "conflates two contracts into one"
     * problem this whole comment describes exists one layer down too --
     * `GraphicsDriver.drawImage()` alone would be the only entry point *any*
     * `currentDriver`-based backend exposes, so a driver whose own
     * `drawImage()` scales `w`/`h` internally (`GdiGraphicsDriver`, via
     * `floorScaled()`) would have no way to know this call's `drawW`/`drawH`
     * are *already* the final device-pixel size, and would silently
     * double-scale every one -- see `GraphicsDriver.drawImageFixed()`'s
     * own doc comment for the fix.
     */
    void drawImageFixed(const(ubyte)* buf, int drawW, int drawH, int drawL, int d, int x, int y)
    {
        if (drawW <= 0 || drawH <= 0 || buf is null) return;
        if (currentDriver !is null)
        {
            currentDriver.drawImageFixed(buf, drawW, drawH, drawL, d, x, y);
            return;
        }
        if (gc_ is null) return;

        int sx = scaledFloor(x), sy = scaledFloor(y);

        // |d| classifies (a negative d is drawImage()'s documented
        // horizontal-flip form); d itself stays signed everywhere it's
        // passed on, since nothing here resamples buf into a normal-
        // order buffer the way drawImage() does -- both callees below
        // walk a signed per-pixel step themselves.
        immutable int ad = d < 0 ? -d : d;
        if (ad == 2 || ad == 4)
        {
            if (alphaBlendImage(buf, sx, sy, drawW, drawH, d, drawL)) return;
            // Destination read failed -- fall through to the always-
            // opaque path, matching drawImage()'s own graceful
            // degradation exactly (see that function's own comment).
        }
        putPackedImage(packImageBuffer(buf, drawW, drawH, d, drawL, false), sx, sy, drawW, drawH);
    }

    /**
     * Composites a gray+alpha (`d==2`) or RGBA (`d==4`) image over
     * whatever is currently drawn at `(x,y,w,h)` on the active
     * drawable, source-over, and blits the blended result back as
     * plain opaque RGB. Ported from `Fl_Xlib_Graphics_Driver`'s own
     * `alpha_blend()` -- see this section's own top comment for why
     * this port needs its manual fallback path unconditionally (no
     * XRender binding exists here to accelerate it). Returns `false`
     * (drawing nothing) if reading the destination back fails, letting
     * the caller fall back to the previous always-opaque path instead.
     * The actual blend math lives in `blendOverRgb()` below (module-
     * level, X-independent, so it gets real headless `unittest`
     * coverage) -- this function is just the X-facing read/blit shell
     * around it.
     *
     * FLTK's own `alpha_blend()` clamps `W`/`H`
     * against the target window's actual size (a live `XGetGeometry()`
     * query) *before* ever calling `fl_read_image()`, specifically so a
     * request extending past the window's edge (e.g. `examples/
     * animgifimage-play`'s 'z' zoom key growing the displayed GIF
     * larger than its window) still reads back and blends the *visible*
     * portion correctly, with only the genuinely off-window remainder
     * silently skipped. Without such a clamp, any
     * out-of-bounds request would make the underlying `XGetImage()` fail for
     * the *entire* rectangle (a `BadMatch`, caught and turned into a
     * plain `null` return -- see `readPixelsFromDrawable()`'s own doc
     * comment), so `drawImage()`'s caller would fall back to its
     * always-opaque path for the *whole* image, not just the
     * off-screen sliver -- losing all transparency the moment any part
     * of a GIF frame extends past its window:
     * transparent regions would turn solid white during playback (or solid
     * black specifically on a freshly-composited first frame, whose
     * `offscreen_` compositing buffer is zero-initialized -- see
     * `fl.anim_gif_image.AnimGifImage.onFrameData()`'s own doc comment).
     */
    private bool alphaBlendImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        // Reads from the same *offset-shifted* location putPackedImage()
        // below will actually write to (that function adds offsetX_/
        // offsetY_ internally) -- otherwise this would composite over
        // whatever's currently at the *unshifted* position instead of
        // the real destination, whenever a translate is active.
        // Matches FLTK's own
        // `Fl_Xlib_Graphics_Driver::alpha_blend()`, which pre-shifts its
        // own X/Y by `offset_x_`/`offset_y_` before reading the
        // destination via `fl_read_image()`. `readPixelsFromDrawable()`
        // itself stays unshifted -- its other caller, `fl_read_image()`
        // (the public capture API), must NOT get an implicit offset,
        // matching FLTK's own `fl_read_image()` (routed through
        // `Fl::screen_driver()`, a class with no `offset_x_`/`offset_y_`
        // concept at all) -- so the shift is applied here, at this call
        // site, not inside that shared function.
        int rx = x + offsetX_, ry = y + offsetY_;
        int rw = w, rh = h;

        // Clamp to the active drawable's own bounds -- ported from
        // `alpha_blend()`'s own `XGetGeometry()`-based clamp (see this
        // function's own doc comment above) --
        // extended past FLTK's own version, which only clamps this
        // (the right/bottom-overflow) side, since it relies on a much
        // more elaborate absolute-screen-coordinate/multi-monitor
        // translation deeper in `read_win_rectangle()` to safely handle
        // the underflow side instead -- machinery this port's own
        // single-window, single-monitor scope has no equivalent of
        // (see `readPixelsFromDrawable()`'s own doc comment on that
        // simplification). A negative `rx`/`ry` here (the *left/top*
        // edge overflowing) is handled
        // directly instead: shift the read/blit rectangle's origin to
        // 0 and shrink it by the overhang, and skip the same amount of
        // the *source* buffer/target position so the visible remainder
        // still lines up correctly -- same net effect as FLTK's
        // own (much larger) mechanism, sized to what this port actually
        // needs.
        int srcSkipX = 0, srcSkipY = 0;
        if (rx < 0) { rw += rx; srcSkipX = -rx; rx = 0; }
        if (ry < 0) { rh += ry; srcSkipY = -ry; ry = 0; }

        uint drawableW, drawableH;
        if (!drawableSize(drawable_, drawableW, drawableH)) return false;
        if (rx + rw > cast(int) drawableW) rw = cast(int) drawableW - rx;
        if (ry + rh > cast(int) drawableH) rh = cast(int) drawableH - ry;
        if (rw <= 0 || rh <= 0) return false;

        auto dst = readPixelsFromDrawable(drawable_, rx, ry, rw, rh);
        if (dst is null) return false;

        // buf's own row stride never shrinks just because the read-back
        // rectangle did -- normalize l (0 means "implicit, == w*d") to
        // an explicit value against the *original* w before rw ever
        // narrows it, so blendOverRgb() walks buf's real row width.
        // (|d| only for the implicit-stride default -- an explicitly
        // given negative `l` is the real vertical-flip form and must
        // stay signed, as must `srcSkipX`'s own per-pixel step.)
        int srcLineDelta = l ? l : w * (d < 0 ? -d : d);
        const(ubyte)* srcBuf = buf + srcSkipY * srcLineDelta + srcSkipX * d;
        blendOverRgb(srcBuf, rw, rh, d, srcLineDelta, dst);

        putPackedImage(packImageBuffer(dst.ptr, rw, rh, 3, rw * 3, false),
            x + srcSkipX, y + srcSkipY, rw, rh);
        return true;
    }

    /// Queries drawable `d`'s current width/height via `XGetGeometry()`.
    /// Returns `false` (leaving `w`/`h` untouched) if the query itself
    /// fails, matching `readPixelsFromDrawable()`'s own "null/false on
    /// any X failure, never an uncaught error" contract.
    private bool drawableSize(Drawable d, out uint w, out uint h)
    {
        if (display_ is null || d == 0) return false;
        Window rootReturn;
        int xReturn, yReturn;
        uint borderWidthReturn, depthReturn;
        return XGetGeometry(display_, d, &rootReturn, &xReturn, &yReturn,
            &w, &h, &borderWidthReturn, &depthReturn) != 0;
    }

    /**
     * Draws a gray-scale (1 channel) image -- ported from
     * `drawImageMono()`. Unlike `drawImage()`, every pixel is
     * treated as a luminance sample (`src[0]`, ignoring the rest of a
     * wider-than-1-byte pixel) regardless of `d`, matching FLTK's
     * own distinct `draw_image_mono()` driver entry point. Scaled via
     * `resampleImageNearest()`/`scaledFloor()`, same as `drawImage()`
     * above -- a no-op at `currentScale() == 1`.
     */
    void drawImageMono(const(ubyte)* buf, int x, int y, int w, int h, int d = 1, int l = 0)
    {
        if (w <= 0 || h <= 0 || buf is null || gc_ is null) return;

        int sx = scaledFloor(x), sy = scaledFloor(y);
        int sw = scaledFloor(x + w) - sx, sh = scaledFloor(y + h) - sy;
        if (sw <= 0 || sh <= 0) return;

        immutable int ad = d < 0 ? -d : d; // see drawImage()'s doc comment
        if (sw != w || sh != h)
        {
            auto resampled = resampleImageNearest(buf, w, h, d, l, sw, sh);
            putPackedImage(packImageBuffer(resampled.ptr, sw, sh, ad, sw * ad, true), sx, sy, sw, sh);
            return;
        }
        putPackedImage(packImageBuffer(buf, w, h, d, l, true), x, y, w, h);
    }

    /**
     * Ported from `Fl_Draw_Image_Cb` (`FL/Fl_Graphics_Driver.H`):
     * `void (*)(void* data, int x, int y, int w, uchar* buf)`. A D
     * delegate instead of a function-pointer + `void*` pair, per this
     * port's usual callback-porting convention (a delegate already
     * closes over whatever context the C version needed `data` for).
     * The callback must fill `buf[0 .. w * d]` with scanline `y`'s
     * pixel data starting at column `x` -- unlike FLTK, `x` is
     * always `0` and `w` always the full image width here, since this
     * port's simplified image-drawing has no clip-driven partial-
     * scanline request to make (see `fl.draw`'s own established
     * "re-convert and re-blit every call, no caching" simplification).
     */
    alias DrawImageCb = void delegate(int x, int y, int w, ubyte[] buf);

    /// Shared driver behind both callback-based entry points below:
    /// materializes the callback's per-scanline output into a plain
    /// buffer, then reuses the raw-buffer packer/blitter above --
    /// FLTK instead blits in bounded-size scanline blocks to cap
    /// peak memory for very large images (`innards()`'s `MAXBUFFER`),
    /// an optimization this port skips, matching its own established
    /// "simplicity over micro-optimization" precedent elsewhere in this
    /// module (e.g. no offscreen-Pixmap image cache either). Scaled the
    /// same `scaledFloor()`/`resampleImageNearest()` way `drawImage()`/
    /// `drawImageMono()` (raw-buffer forms) are -- a no-op at
    /// `currentScale() == 1`.
    private void drawImageViaCallback(DrawImageCb cb, int x, int y, int w, int h, int d, bool mono)
    {
        if (w <= 0 || h <= 0 || cb is null || gc_ is null) return;
        auto raw = new ubyte[w * h * d];
        auto line = new ubyte[w * d];
        for (int row = 0; row < h; row++)
        {
            cb(0, row, w, line);
            raw[row * w * d .. (row + 1) * w * d] = line[];
        }

        int sx = scaledFloor(x), sy = scaledFloor(y);
        int sw = scaledFloor(x + w) - sx, sh = scaledFloor(y + h) - sy;
        if (sw <= 0 || sh <= 0) return;

        if (sw != w || sh != h)
        {
            auto resampled = resampleImageNearest(raw.ptr, w, h, d, w * d, sw, sh);
            putPackedImage(packImageBuffer(resampled.ptr, sw, sh, d, sw * d, mono), sx, sy, sw, sh);
            return;
        }
        putPackedImage(packImageBuffer(raw.ptr, w, h, d, w * d, mono), x, y, w, h);
    }

    /// Draws an image using a callback to generate scan-line data.
    /// Ported from `fl_draw_image(Fl_Draw_Image_Cb, void*, ...)`.
    void drawImage(DrawImageCb cb, int x, int y, int w, int h, int d = 3)
    {
        drawImageViaCallback(cb, x, y, w, h, d, false);
    }

    /// Gray-scale counterpart of the callback-based `drawImage()`
    /// above. Ported from `fl_draw_image_mono(Fl_Draw_Image_Cb, void*, ...)`.
    void drawImageMono(DrawImageCb cb, int x, int y, int w, int h, int d = 1)
    {
        drawImageViaCallback(cb, x, y, w, h, d, true);
    }

    /**
     * Creates a cached 1-bit X Pixmap ("bitmask") from bits (dataW()
     * rows of `(dataW()+7)/8` bytes each) -- the server-side resource
     * `Fl_Bitmap`'s stipple-fill draw() uses. Ported from
     * `Fl_Xlib_Graphics_Driver::create_bitmask()`. Returned as a plain
     * `ulong` (matching FLTK's own opaque `fl_uintptr_t id_`
     * field), not `fl.xlib.Pixmap`, so `fl.bitmap` (like `fl.image`)
     * doesn't need to import `fl.xlib` itself.
     */
    ulong createBitmask(int dataW, int dataH, const(ubyte)* bits)
    {
        if (display_ is null || drawable_ == 0) return 0;
        return cast(ulong) XCreateBitmapFromData(display_, drawable_,
            cast(const(ubyte)*) bits, (dataW + 7) & ~7, dataH);
    }

    /// Frees a bitmask created by createBitmask(). A no-op for id 0
    /// (never created, or already freed) -- matching every other
    /// uncache()-style function in this port that guards the same way.
    void freeBitmask(ulong id)
    {
        if (id == 0) return;
        XFreePixmap(display_, cast(Pixmap) id);
    }

    /**
     * Draws a 1-bit bitmap via the classic X11 stipple-fill technique
     * (the current color shows through wherever a bit is set) --
     * ported from `Fl_Xlib_Graphics_Driver::draw_fixed(Fl_Bitmap*,...)`.
     * `id` is a cache slot the caller owns (see createBitmask()) --
     * created lazily here on first draw, matching FLTK's own
     * `cache()`-on-first-use pattern, just inlined rather than routed
     * through a separate cache() entry point (nothing else in this
     * port needs to cache a bitmask ahead of the first draw).
     *
     * Scaled: without this, `fl.adjuster.Adjuster`'s own arrow
     * glyphs would stay the same on-screen size during a live Ctrl-+/-
     * rescale while everything drawn around them grows. Two separate
     * halves, split the same way FLTK splits them across
     * `Fl_Graphics_Driver::draw_bitmap()` (recache-at-the-right-size)
     * and `Fl_Xlib_Graphics_Driver::draw_fixed()` (scale the
     * destination rect) -- except this port's caller
     * (`fl.bitmap.Bitmap.draw()`) owns the *first* half itself (it
     * already resets `id` to 0 and re-resamples `bits`/`dataW`/`dataH`
     * via its own real `copy()` port whenever the current scale no
     * longer matches what `id` was last built at -- see that method's
     * own doc comment), so `dataW`/`dataH`/`bits` here are already
     * whatever resolution the caller decided to cache them at; this
     * function only needs the *second* half, scaling the destination
     * rect and bitmap offset to device pixels -- the same
     * `scaledFloor(x+w)-scaledFloor(x)` edge-alignment `fl_rectf()`
     * already uses, so adjacent shapes stay pixel-aligned. `dataW`/
     * `dataH` themselves are deliberately *not* scaled again here (only
     * used for the `XSetTSOrigin()` wrap-around math below) -- they're
     * already the resampled bitmap's own real size, matching FLTK's
     * own `bm->w()*scale()` at the equivalent spot exactly (the
     * resampled bitmap's `w()`/`h()` already equal that product).
     */
    void drawBitmapFixed(ref ulong id, int dataW, int dataH, const(ubyte)* bits,
        int X, int Y, int W, int H, int cx, int cy)
    {
        if (currentDriver !is null)
        {
            currentDriver.drawBitmap(bits, dataW, dataH, X, Y, W, H, cx, cy);
            return;
        }
        if (gc_ is null) return;
        if (id == 0) id = createBitmask(dataW, dataH, bits);
        if (id == 0) return;

        int sx = scaledFloor(X), sy = scaledFloor(Y);
        int sw = scaledFloor(X + W) - sx;
        int sh = scaledFloor(Y + H) - sy;
        int scx = scaledFloor(cx), scy = scaledFloor(cy);

        // Shifted once, up front -- both the stipple origin and the
        // fill rectangle need to move together, matching FLTK's own
        // `X = floor(X)+floor(offset_x_); Y = floor(Y)+floor(offset_y_);`
        // at the top of `draw_fixed(Fl_Bitmap*,...)` --
        // `offsetX_`/`offsetY_` are already device-pixel
        // values (added *after* scaling), matching `fl_rectf()`'s own
        // `sx + offsetX_` order exactly.
        sx += offsetX_;
        sy += offsetY_;

        XSetStipple(display_, gc_, cast(Pixmap) id);
        int ox = sx - scx;
        if (ox < 0) ox += dataW;
        int oy = sy - scy;
        if (oy < 0) oy += dataH;
        XSetTSOrigin(display_, gc_, ox, oy);
        XSetFillStyle(display_, gc_, FillStippled);
        XFillRectangle(display_, drawable_, gc_, sx, sy, cast(uint) sw, cast(uint) sh);
        XSetFillStyle(display_, gc_, FillSolid);
    }

    /**
     * `XSetErrorHandler()` callback that swallows exactly the async
     * `BadMatch` `XGetImage()` raises when the requested rectangle
     * extends outside the target drawable -- an expected, common
     * outcome for `readPixelsFromDrawable()`'s callers (e.g. reading
     * back a rectangle sized against a different geometry than the
     * source drawable actually has), not a rare race. Xlib's *default*
     * error handler prints the error and calls `exit()`, which would
     * otherwise take the whole process down over a failed capture that
     * should just return `null` -- e.g. `exit(1)`,
     * `BadMatch ... X_GetImage`, when capturing an oddly-shaped GIF frame.
     * Matches FLTK's own `Fl_X11_Screen_Driver::read_win_rectangle()`,
     * which wraps its `XGetImage()`/`XGetSubImage()` calls the same way
     * (its own `xgetimageerrhandler`, a temporary, locally-scoped
     * handler swap restored right after the call) -- kept separate
     * from `fl.platform_x11`'s own global `installErrorHandler()`,
     * which is deliberately narrow/rare-race-only; this one is
     * common/expected, so it gets its own local scope here instead of
     * growing that list.
     */
    extern (C) private int ignoreXGetImageError(Display* display, XErrorEvent* event) @nogc nothrow
    {
        return 0;
    }

    /**
     * Reads RGB(A) pixels back from an X11 drawable via `XGetImage()`.
     * Ported from `Fl_X11_Screen_Driver::read_win_rectangle()`
     * (`src/drivers/X11/Fl_X11_Screen_Driver.cxx`), radically
     * simplified in the same direction as the rest of this module:
     * FLTK supports every visual depth/byte order plus an indexed-
     * colormap fallback (a 4096-entry `XQueryColors()` table, for
     * `bits_per_pixel` in {1,2,4,8,12}) and multi-monitor screen-
     * crossing subimage logic; this port already assumes a plain
     * 8-8-8 TrueColor visual everywhere else (see `fl_color()`'s own
     * doc comment) and single-monitor-unaware direct capture, so this
     * function does too -- only `bits_per_pixel` 16/24/32 (every
     * realistic modern X server) are unpacked, using this port's own
     * fixed `(r<<16)|(g<<8)|b` channel layout directly (mirroring
     * `packImageBuffer()`'s own byte layout above, for round-trip
     * consistency) rather than deriving shifts from `image.red_mask`
     * like FLTK does for portability across visual types. Returns
     * `null` if the display isn't open, the rectangle is degenerate,
     * or the underlying `XGetImage()` fails (e.g. the rectangle
     * extends outside the drawable) -- matching FLTK's own
     * NULL-on-failure contract, made real by the temporary error-
     * handler swap around the `XGetImage()` call itself (see
     * `ignoreXGetImageError()`'s own doc comment).
     */

    package(fl) ubyte[] readPixelsFromDrawable(Drawable d, int x, int y, int w, int h, int alpha = 0)
    {
        if (display_ is null || d == 0 || w <= 0 || h <= 0) return null;

        // XGetImage() raises an asynchronous BadMatch protocol error
        // (not a synchronous NULL return) whenever the requested
        // rectangle extends outside the drawable -- an expected,
        // common occurrence for this function's callers (e.g. reading
        // back a scaled/resized copy sized differently than the
        // source drawable), not a rare race. Without a custom handler
        // installed, Xlib's *default* error handler prints the error
        // and calls exit(), taking the whole process down over what
        // should just be a failed capture -- e.g. a
        // crash (SIGABRT via exit(1), "BadMatch ... X_GetImage")
        // capturing an oddly-shaped GIF frame. Matches FLTK's own
        // `Fl_X11_Screen_Driver::read_win_rectangle()`, which wraps its
        // XGetImage()/XGetSubImage() calls the same way (a temporary,
        // locally-scoped handler swap, restored right after -- kept
        // separate from fl.platform_x11's own global installErrorHandler()`,
        // which is deliberately narrow/rare-race-only; this one is
        // common/expected, so it gets its own local scope instead of
        // growing that list).
        auto oldHandler = XSetErrorHandler(&ignoreXGetImageError);
        auto image = XGetImage(display_, d, x, y, cast(uint) w, cast(uint) h, AllPlanes, ZPixmap);
        XSetErrorHandler(oldHandler);
        if (image is null) return null;
        scope(exit) XDestroyImage(image);

        int depth = alpha ? 4 : 3;
        ubyte alphaByte = cast(ubyte) alpha;
        auto result = new ubyte[w * h * depth];

        for (int row = 0; row < h; row++)
        {
            const(ubyte)* line = cast(const(ubyte)*) image.data + row * image.bytes_per_line;
            ubyte* outPixel = result.ptr + row * w * depth;
            for (int col = 0; col < w; col++)
            {
                ubyte r, g, b;
                if (image.bits_per_pixel == 32)
                {
                    const(ubyte)* p = line + col * 4;
                    if (image.byte_order == MSBFirst) { r = p[1]; g = p[2]; b = p[3]; }
                    else { b = p[0]; g = p[1]; r = p[2]; }
                }
                else if (image.bits_per_pixel == 24)
                {
                    const(ubyte)* p = line + col * 3;
                    if (image.byte_order == MSBFirst) { r = p[0]; g = p[1]; b = p[2]; }
                    else { b = p[0]; g = p[1]; r = p[2]; }
                }
                else if (image.bits_per_pixel == 16)
                {
                    ushort pixel = (cast(const(ushort)*)(line + col * 2))[0];
                    r = cast(ubyte) (((pixel >> 11) & 0x1F) * 255 / 31);
                    g = cast(ubyte) (((pixel >> 5) & 0x3F) * 255 / 63);
                    b = cast(ubyte) ((pixel & 0x1F) * 255 / 31);
                }
                else
                {
                    // Unsupported depth -- shouldn't happen on any
                    // modern TrueColor X server (see this function's
                    // own doc comment for the deliberate scope cut).
                    r = g = b = 0;
                }
                outPixel[0] = r;
                outPixel[1] = g;
                outPixel[2] = b;
                if (alpha) outPixel[3] = alphaByte;
                outPixel += depth;
            }
        }
        return result;
    }

    /**
     * Reads an RGB(A) image from the currently active drawable
     * (whatever `setDrawable()` last pointed `drawable_` at -- a real
     * window or a `DoubleWindow`'s off-screen buffer, matching
     * FLTK's own "reads from the current window or off-screen
     * buffer" semantics without needing to distinguish the two, since
     * this port's `drawable_` already *is* whichever one is currently
     * active). Ported from `fl_read_image()` (`src/readImage.cxx`)
     * -- see `readPixelsFromDrawable()`'s own doc comment for the
     * simplifications. Unlike FLTK, there's no caller-supplied-
     * buffer-to-reuse parameter (`uchar* p`) -- the GC already makes
     * that C-memory-reuse optimization moot, same substitution this
     * port makes everywhere else a C API hands back a manually-
     * `delete[]`d buffer (see `Widget.label()`'s own doc comment).
     * `alpha`, if nonzero, is written into every pixel's alpha byte
     * (matching FLTK exactly -- this reads real drawn RGB data
     * only, it can't recover per-pixel transparency that was never
     * drawn in the first place).
     *
     * **Caveat** (see `smoke-tests/read_image.d`): unlike ordinary drawing calls, the underlying
     * `XGetImage()` *requires* the target window to be "viewable" (X11
     * protocol term: mapped, with every ancestor also mapped) or the
     * server raises a real `BadMatch` error. Calling this from a
     * widget's very first `draw()` can lose that race in this port
     * specifically: `fl.platform_x11.wait()`'s first iteration calls
     * `flushDamage()` (and so `draw()`) unconditionally, before the
     * window has necessarily received the server's own confirming
     * `Expose`/`MapNotify` -- fine for plain drawing requests (the
     * server just queues them regardless), not fine for this function.
     * Call it after the window is confirmed shown/exposed instead (an
     * `addTimeout()`-deferred check, or from a later `draw()` pass
     * triggered by a real subsequent event, both work) rather than
     * synchronously inside a first-paint `draw()` override.
     */
    ubyte[] readImage(int x, int y, int w, int h, int alpha = 0)
    {
        return readPixelsFromDrawable(drawable_, x, y, w, h, alpha);
    }

    // ---------------------------------------------------------------
    // overlayRect()/overlayClear() -- transient dotted
    // selection-rectangle support. Ported from `src/fl_overlay.cxx`.
    // ---------------------------------------------------------------

    private int ovX_, ovY_, ovW_, ovH_;

    /// One saved device-pixel strip of whatever sat under one edge of
    /// the current overlay rectangle (see `overlaySaveStrip()`) -- same
    /// shape as the `version (Windows)` twin's own `OverlayStrip`.
    private struct OverlayStrip
    {
        fl.xlib.Pixmap pixmap;
        int x, y, w, h; // device pixels, in drawable_'s own coordinates
    }
    private OverlayStrip[4] ovStrips_;

    /// Ported from `Fl_Graphics_Driver::overlay_rect()`
    /// (`Fl_Graphics_Driver.cxx`) -- a plain rectangle outline via the
    /// already-real transform-stack/vertex-loop primitives.
    private void overlayDrawRectPrimitive(int x, int y, int w, int h)
    {
        beginLoop();
        vertex(x, y);
        vertex(x + w - 1, y);
        vertex(x + w - 1, y + h - 1);
        vertex(x, y + h - 1);
        endLoop();
    }

    /// Saves the device pixels under the logical strip `(lx,ly,lw,lh)`
    /// into `strip`, via a plain `XCreatePixmap()`+`XCopyArea()`.
    ///
    /// Deliberately device-pixel-exact rather than going through
    /// `readImage()`/`drawImage()`: at any scale other than 100%, a 1-FLTK-unit edge is
    /// several device pixels wide (and a scaled pen can spill past it --
    /// `lineStyle()` widens it to `int(scale)` at >= 200%), while
    /// `readPixelsFromDrawable()` reads raw, unscaled device coordinates
    /// and `drawImage()` then stretches the result to a `floorScaled()`
    /// box, the old edge pixels would never be fully restored and the
    /// rectangle would leave trails (`FIXME-rectangle` -- see
    /// `overlaySaveStrip()` in the `version (Windows)` block below,
    /// which this is a direct X11 port of). The strip is padded by
    /// `ceil(scale)` device pixels on every side (none at 100%, keeping
    /// that case identical to FLTK's) to cover the scaled pen's own
    /// spill past the logical edge.
    private void overlaySaveStrip(ref OverlayStrip strip, int lx, int ly, int lw, int lh)
    {
        import std.math : ceil, floor;

        strip = OverlayStrip.init;
        if (display_ is null || drawable_ == 0) return;

        float s = currentScale();
        int m = s == 1 ? 0 : cast(int) ceil(s);
        int x0 = cast(int) floor(lx * s) - m;
        int y0 = cast(int) floor(ly * s) - m;
        int x1 = cast(int) floor((lx + lw) * s) + m;
        int y1 = cast(int) floor((ly + lh) * s) + m;
        if (x1 <= x0 || y1 <= y0) return;

        auto pixmap = createOffscreenBuffer(drawable_, x1 - x0, y1 - y0);
        if (pixmap == 0) return;
        XCopyArea(display_, drawable_, pixmap, gc_, x0, y0, cast(uint)(x1 - x0), cast(uint)(y1 - y0), 0, 0);
        strip = OverlayStrip(pixmap, x0, y0, x1 - x0, y1 - y0);
    }

    private void overlayFreeStrips()
    {
        foreach (ref strip; ovStrips_)
        {
            if (strip.pixmap != 0) freeOffscreenBuffer(strip.pixmap);
            strip = OverlayStrip.init;
        }
    }

    private void overlayDrawCurrentRect()
    {
        overlayFreeStrips();
        if (ovW_ > 0 && ovH_ > 0)
        {
            overlaySaveStrip(ovStrips_[0], ovX_, ovY_, ovW_, 1);            // N
            overlaySaveStrip(ovStrips_[1], ovX_, ovY_ + ovH_ - 1, ovW_, 1); // S
            overlaySaveStrip(ovStrips_[2], ovX_, ovY_, 1, ovH_);            // W
            overlaySaveStrip(ovStrips_[3], ovX_ + ovW_ - 1, ovY_, 1, ovH_); // E
        }

        fl_color(white);
        lineStyle(lineSolid);
        overlayDrawRectPrimitive(ovX_, ovY_, ovW_, ovH_);

        fl_color(black);
        lineStyle(lineDot);
        overlayDrawRectPrimitive(ovX_, ovY_, ovW_, ovH_);

        lineStyle(lineSolid);
    }

    private void overlayEraseCurrentRect()
    {
        if (display_ !is null && gc_ !is null)
        {
            foreach (ref strip; ovStrips_)
            {
                if (strip.pixmap == 0) continue;
                XCopyArea(display_, strip.pixmap, drawable_, gc_, 0, 0,
                    cast(uint) strip.w, cast(uint) strip.h, strip.x, strip.y);
            }
        }
        overlayFreeStrips();
    }

    /**
     * Erases a selection rectangle previously drawn by `overlayRect()`
     * without drawing a new one. Ported from `fl_overlay_clear()`
     * (`src/fl_overlay.cxx`).
     */
    void overlayClear()
    {
        if (ovW_ > 0)
        {
            overlayEraseCurrentRect();
            ovW_ = 0;
        }
    }

    /**
     * Draws a transient dotted selection rectangle directly into the
     * currently active drawable, saving whatever was under its 4 edge
     * strips first so a later `overlayClear()` can restore them
     * without a full redraw. Ported from `fl_overlay_rect()`
     * (`src/fl_overlay.cxx`) -- see that file's own doc comment for the
     * intended call pattern: call from `FL_PUSH`/`FL_DRAG`/`FL_RELEASE`
     * handlers, after `window()->make_current()` (`window().makeCurrent()`
     * in this port), never from `draw()`.
     *
     * Simplified relative to FLTK: the 4 saved edge strips are plain
     * `ubyte[]` RGB buffers read/restored device-pixel-exact via
     * `overlaySaveStrip()`'s own direct `XCreatePixmap()`/`XCopyArea()`
     * pair, not `fl_read_image()`/`drawImage()` -- see that function's
     * own doc comment for why: both of those are scale-aware now, which
     * would stretch/resample the saved strip on restore and leave
     * trails at any scale other than 100%.
     */
    void overlayRect(int x, int y, int w, int h)
    {
        if (ovW_ > 0)
        {
            if (x == ovX_ && y == ovY_ && w == ovW_ && h == ovH_) return;
            overlayEraseCurrentRect();
        }

        // Width and height must be positive, swap with coordinates if needed.
        if (w < 0) { x += w; w = -w; }
        if (h < 0) { y += h; h = -h; }

        // Clip the overlay to the window rect, or reading the
        // background above would fail.
        uint winW, winH;
        if (drawableSize(drawable_, winW, winH))
        {
            int d;
            d = -x; if (d > 0) { x += d; w -= d; }
            d = (x + w) - cast(int) winW; if (d > 0) w -= d;
            d = -y; if (d > 0) { y += d; h -= d; }
            d = (y + h) - cast(int) winH; if (d > 0) h -= d;
        }

        if (w < 1) w = 1;
        if (h < 1) h = 1;

        // Store the rect so we can erase it later.
        ovX_ = x; ovY_ = y; ovW_ = w; ovH_ = h;

        // Draw it.
        overlayDrawCurrentRect();
    }
}
else
{
    import core.sys.windows.windows;
    import fl.gdi_graphics_driver : GdiGraphicsDriver;

    /// Real native on-screen GDI image/bitmap drawing:
    /// `fl.gdi_graphics_driver.GdiGraphicsDriver` overrides
    /// `GraphicsDriver.drawImage()`/`drawBitmap()`, so
    /// both leaves below just forward to `currentDriver`, which covers
    /// on-screen GDI rendering, not just the *surface-device*
    /// drivers (`fl.postscript`'s/`fl.svg_file_surface`'s own
    /// `GraphicsDriver` subclasses, active via `SurfaceDevice.
    /// pushCurrent()`) -- matching the
    /// `version (linux)` `drawImage()` above exactly. See
    /// `GdiGraphicsDriver.drawImage()`/`drawBitmap()`'s own doc comments
    /// for the real GDI implementation.
    ///
    /// `drawImageFixed()` dispatches to `currentDriver.drawImageFixed()`,
    /// not `.drawImage()` -- see `fl.graphics_driver.
    /// GraphicsDriver.drawImageFixed()`'s own doc comment for the
    /// contract-ambiguity this avoids and `GdiGraphicsDriver.
    /// drawImageFixed()`'s override for the real GDI-side implementation.
    void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d = 3, int l = 0)
    {
        if (currentDriver !is null) currentDriver.drawImage(buf, x, y, w, h, d, l);
    }
    void drawImageFixed(const(ubyte)* buf, int drawW, int drawH, int drawL, int d, int x, int y)
    {
        if (currentDriver !is null) currentDriver.drawImageFixed(buf, drawW, drawH, drawL, d, x, y);
    }
    /// Gray-scale counterpart of the raw-buffer `drawImage()` above.
    /// Ported from `draw_image_mono()`. `source/test/DrawingArea.d`
    /// (the `mandelbrot` sample)'s own default (non-color) rendering
    /// mode calls this directly every frame, so it needs a real
    /// implementation on Windows too. Every pixel is a luminance sample (`src[0]` of
    /// each `d`-byte-stride pixel, matching FLTK's own
    /// `draw_image_mono()` contract regardless of `d`) -- repacked into
    /// a tightly-packed 1-byte-per-pixel buffer and handed to the
    /// already-real raw-buffer `drawImage()` above (whose own `d == 1`
    /// case already treats a byte as gray), except in the already-
    /// tightly-packed common case (`d == 1 && l == w`), which skips the
    /// repack entirely and calls straight through.
    void drawImageMono(const(ubyte)* buf, int x, int y, int w, int h, int d = 1, int l = 0)
    {
        if (buf is null || w <= 0 || h <= 0) return;
        // |d| for the implicit row-stride default only -- a negative `d`
        // is the horizontal-flip form (see the `version (linux)`
        // `drawImage()`'s own doc comment), whose per-pixel step below
        // stays signed.
        if (l == 0) l = w * (d < 0 ? -d : d);
        if (d == 1 && l == w)
        {
            drawImage(buf, x, y, w, h, 1, l);
            return;
        }
        auto gray = new ubyte[w * h];
        foreach (row; 0 .. h)
        {
            const(ubyte)* src = buf + row * l;
            ubyte* dst = gray.ptr + row * w;
            foreach (col; 0 .. w) dst[col] = src[col * d];
        }
        drawImage(gray.ptr, x, y, w, h, 1, w);
    }
    alias DrawImageCb = void delegate(int x, int y, int w, ubyte[] buf);

    /// Materializes the callback's per-scanline output into a plain
    /// buffer, then reuses the raw-buffer `drawImage()` above -- mirrors
    /// the `version (linux)` `drawImageViaCallback()`'s own materialize-
    /// then-blit shape (that one packs into an X `Pixmap` via
    /// `putPackedImage()`; on Windows there's no equivalent packed-image
    /// cache to build, so this just calls straight through to
    /// `currentDriver.drawImage()` via the raw-buffer `drawImage()` just
    /// above). `fl.color_chooser`'s `HueBox`/`ValueBox` gradients are
    /// this case (see that module's own top comment: ported to call
    /// "the real fl_draw_image()"'s callback-based overload
    /// specifically), along with `color_chooser`,
    /// `colbrowser`, and `contrast`'s color chooser popup gradients.
    private void drawImageViaCallback(DrawImageCb cb, int x, int y, int w, int h, int d)
    {
        if (w <= 0 || h <= 0 || cb is null) return;
        auto raw = new ubyte[w * h * d];
        auto line = new ubyte[w * d];
        foreach (row; 0 .. h)
        {
            cb(0, row, w, line);
            raw[row * w * d .. (row + 1) * w * d] = line[];
        }
        drawImage(raw.ptr, x, y, w, h, d, w * d);
    }

    /// Draws an image using a callback to generate scan-line data.
    /// Ported from `fl_draw_image(Fl_Draw_Image_Cb, void*, ...)`.
    void drawImage(DrawImageCb cb, int x, int y, int w, int h, int d = 3)
    {
        drawImageViaCallback(cb, x, y, w, h, d);
    }

    /// Gray-scale counterpart of the callback-based `drawImage()` above.
    /// Ported from `fl_draw_image_mono(Fl_Draw_Image_Cb, void*, ...)`.
    void drawImageMono(DrawImageCb cb, int x, int y, int w, int h, int d = 1)
    {
        drawImageViaCallback(cb, x, y, w, h, d);
    }
    /// Deliberately still stubs -- dead code on this
    /// platform, not an overlooked gap: both
    /// callers that own a bitmask id (`fl.bitmap.Bitmap.draw()` via
    /// `drawBitmapFixed()` just below, `fl.pixmap.Pixmap.draw()` via
    /// `setClipMask()`/`clearClipMask()` further down this file) always
    /// check `if (currentDriver !is null) { ...; return; }` *before*
    /// ever touching the bitmask -- and `fl.platform_win32.
    /// ensureGraphicsDriver()` unconditionally installs a real
    /// `currentDriver` (GDI+, or plain GDI on fallback) for every
    /// on-screen window, so that branch is the *only* one Windows ever
    /// reaches. `Pixmap.draw()`'s own `currentDriver` branch already
    /// draws real per-pixel transparency (RGBA via `drawImageFixed()`,
    /// not a binary clip mask) instead, so nothing is missing in
    /// practice -- these exist only for the `currentDriver is null`
    /// legacy-GC path, which has no Windows equivalent to be null in.
    ulong createBitmask(int dataW, int dataH, const(ubyte)* bits) { return 0; }
    void freeBitmask(ulong id) { }
    void drawBitmapFixed(ref ulong id, int dataW, int dataH, const(ubyte)* bits,
        int X, int Y, int W, int H, int cx, int cy)
    {
        if (currentDriver !is null) currentDriver.drawBitmap(bits, dataW, dataH, X, Y, W, H, cx, cy);
    }

    /**
     * Reads RGB(A) pixels back via GDI. Ported from the same
     * `fl_read_image()`/`read_win_rectangle()` contract the
     * `version (linux)` `readPixelsFromDrawable()` implements (see that
     * function's own doc comment for the exact return-buffer shape: top-
     * down rows, `alpha`-if-nonzero stamped into every pixel's 4th byte).
     * `source/test/DrawingArea.d`'s `printCb()` reaches this
     * directly (an
     * unguarded `readImage()` call, not behind any `version (linux)`).
     *
     * `d`, when nonzero, names an `Offscreen` (`HBITMAP`, matching this
     * module's other `size_t`-typed opaque-id convention) to read from
     * instead of the currently active drawable -- `makeDcFor()` (above)
     * gives it a temporary DC the same way `beginOffscreen()` does.
     * `d == 0` means "whatever's currently active", matching
     * `readImage()`'s own FLTK semantics: reads from
     * `GdiGraphicsDriver.hdc()`, which already *is* whichever real
     * window or offscreen bitmap is currently being drawn to (see
     * `beginOffscreen()`'s own doc comment) -- no separate "current
     * drawable" tracker needed the way Linux's `drawable_` is, since
     * `hdc()` already plays that role.
     *
     * GDI has no direct "read pixels from an arbitrary DC" call the way
     * `XGetImage()` reads from any drawable directly -- `GetDIBits()`
     * only reads from a real `HBITMAP` object, not a DC in the
     * abstract (a window's DC has no bitmap of its own to query). So
     * this first `BitBlt()`s the requested rectangle into a fresh
     * compatible bitmap, then `GetDIBits()`s *that* -- the standard
     * WinAPI two-step for capturing arbitrary on-screen pixels,
     * matching FLTK's own `Fl_WinAPI_Screen_Driver::read_win_
     * rectangle()` (`CreateCompatibleBitmap()`+`BitBlt()`+`GetDIBits()`).
     * Requests a top-down (`biHeight` negative) 24bpp DIB -- GDI still
     * pads each row to a 4-byte boundary regardless of bit depth, so
     * the unpack loop below reads by that stride, not `w*3`.
     */
    package(fl) ubyte[] readPixelsFromDrawable(size_t d, int x, int y, int w, int h, int alpha = 0)
    {
        if (w <= 0 || h <= 0) return null;

        HDC ownDc;
        HDC srcDc;
        if (d != 0)
        {
            ownDc = makeDcFor(cast(HBITMAP) d);
            srcDc = ownDc;
        }
        else
        {
            auto driver = cast(GdiGraphicsDriver) currentDriver;
            if (driver is null || driver.hdc() is null) return null;
            srcDc = driver.hdc();
        }
        scope(exit) if (ownDc !is null) DeleteDC(ownDc);

        HDC memDc = CreateCompatibleDC(srcDc);
        if (memDc is null) return null;
        scope(exit) DeleteDC(memDc);
        HBITMAP memBmp = CreateCompatibleBitmap(srcDc, w, h);
        if (memBmp is null) return null;
        scope(exit) DeleteObject(memBmp);
        auto oldObj = SelectObject(memDc, memBmp);
        BitBlt(memDc, 0, 0, w, h, srcDc, x, y, SRCCOPY);
        SelectObject(memDc, oldObj);

        BITMAPINFO bmi;
        bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
        bmi.bmiHeader.biWidth = w;
        bmi.bmiHeader.biHeight = -h;
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 24;
        bmi.bmiHeader.biCompression = BI_RGB;

        int stride = ((w * 3 + 3) / 4) * 4;
        auto dib = new ubyte[stride * h];
        if (GetDIBits(memDc, memBmp, 0, h, dib.ptr, &bmi, DIB_RGB_COLORS) == 0)
            return null;

        int depth = alpha ? 4 : 3;
        ubyte alphaByte = cast(ubyte) alpha;
        auto result = new ubyte[w * h * depth];
        foreach (row; 0 .. h)
        {
            const(ubyte)* src = dib.ptr + row * stride;
            ubyte* outp = result.ptr + row * w * depth;
            foreach (col; 0 .. w)
            {
                // DIBs are always BGR(A), never RGB -- swap on the way out.
                outp[0] = src[col * 3 + 2];
                outp[1] = src[col * 3 + 1];
                outp[2] = src[col * 3 + 0];
                if (alpha) outp[3] = alphaByte;
                outp += depth;
            }
        }
        return result;
    }

    /// Reads back from whichever drawable is currently active. Ported
    /// from `fl_read_image()`. See `readPixelsFromDrawable()`'s own doc
    /// comment for the exact contract.
    ubyte[] readImage(int x, int y, int w, int h, int alpha = 0)
    {
        return readPixelsFromDrawable(0, x, y, w, h, alpha);
    }

    /// The reverse of `readPixelsFromDrawable()`: writes tightly packed
    /// RGB pixels (`w * h * 3` bytes) to device pixel (0,0) of `d`, or of
    /// the currently active drawable when `d == 0`, unscaled. Used by
    /// `fl.image_surface.ImageSurface.image()` to store a masked blend,
    /// the job `SetDIBits()` does in `Fl_GDI_Image_Surface_Driver::image()`.
    package(fl) void writePixelsToDrawable(size_t d, const(ubyte)[] rgb, int w, int h)
    {
        if (w <= 0 || h <= 0 || rgb.length < cast(size_t) w * h * 3) return;

        HDC ownDc;
        HDC dstDc;
        if (d != 0)
        {
            ownDc = makeDcFor(cast(HBITMAP) d);
            dstDc = ownDc;
        }
        else
        {
            auto driver = cast(GdiGraphicsDriver) currentDriver;
            if (driver is null || driver.hdc() is null) return;
            dstDc = driver.hdc();
        }
        scope(exit) if (ownDc !is null) DeleteDC(ownDc);

        int stride = ((w * 3 + 3) / 4) * 4;
        auto dib = new ubyte[stride * h];
        foreach (row; 0 .. h)
        {
            const(ubyte)* src = rgb.ptr + row * w * 3;
            ubyte* dst = dib.ptr + row * stride;
            foreach (col; 0 .. w)
            {
                // RGB in, BGR in the DIB.
                dst[col * 3 + 0] = src[col * 3 + 2];
                dst[col * 3 + 1] = src[col * 3 + 1];
                dst[col * 3 + 2] = src[col * 3 + 0];
            }
        }

        BITMAPINFO bmi;
        bmi.bmiHeader.biSize = BITMAPINFOHEADER.sizeof;
        bmi.bmiHeader.biWidth = w;
        bmi.bmiHeader.biHeight = -h; // top-down
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 24;
        bmi.bmiHeader.biCompression = BI_RGB;
        SetDIBitsToDevice(dstDc, 0, 0, cast(DWORD) w, cast(DWORD) h, 0, 0, 0,
            cast(UINT) h, dib.ptr, &bmi, DIB_RGB_COLORS);
    }

    // ---------------------------------------------------------------
    // overlayRect()/overlayClear() -- transient dotted selection-
    // rectangle support. Ported from `src/fl_overlay.cxx`, same shape
    // as the `version (linux)` implementation above, except that the
    // background under each edge is saved/restored as exact device
    // pixels via GDI `BitBlt()` rather than `readImage()`/`drawImage()`
    // (see `overlaySaveStrip()` for why -- scaled displays would leave trails
    // otherwise). `source/test/DrawingArea.d`'s
    // rubber-band selection (`handle()`'s `Event.drag` case) and its
    // `eraseBox()` helper reach this directly.
    // ---------------------------------------------------------------

    private int ovX_, ovY_, ovW_, ovH_;

    /// One saved device-pixel strip of whatever sat under one edge of the
    /// current overlay rectangle (see `overlaySaveStrip()`).
    private struct OverlayStrip
    {
        HBITMAP bmp;
        int x, y, w, h; // device pixels, in the target DC's own coordinates
    }
    private OverlayStrip[4] ovStrips_;

    private void overlayDrawRectPrimitive(int x, int y, int w, int h)
    {
        beginLoop();
        vertex(x, y);
        vertex(x + w - 1, y);
        vertex(x + w - 1, y + h - 1);
        vertex(x, y + h - 1);
        endLoop();
    }

    /// Saves the device pixels under the logical strip `(lx,ly,lw,lh)`
    /// into `strip`, via a plain `BitBlt()` into a compatible bitmap.
    ///
    /// Deliberately device-pixel-exact rather than going through
    /// `readImage()`/`drawImage()` the way the `version (linux)` twin
    /// does: at any scale other than 100%, a 1-FLTK-unit edge is several
    /// device pixels wide (and a scaled pen can spill past it --
    /// `lineStyle()` widens it to `int(scale)` at >= 200%), while
    /// `readPixelsFromDrawable()` reads raw, unscaled device coordinates
    /// and `drawImage()` then stretches the result to a `floorScaled()`
    /// box, so the old edge pixels were never fully restored and the
    /// rectangle left trails. FLTK gets the same exactness from
    /// `read_win_rectangle()` returning a device-resolution image that
    /// `Fl_RGB_Image::scale()` then pins to the logical size. The strip
    /// is padded by `ceil(scale)` device pixels on every side (none at
    /// 100%, keeping that case identical to FLTK's) to cover the
    /// scaled pen's own spill past the logical edge.
    private void overlaySaveStrip(HDC dc, ref OverlayStrip strip, int lx, int ly, int lw, int lh)
    {
        import std.math : ceil, floor;

        strip = OverlayStrip.init;
        float s = currentScale();
        int m = s == 1 ? 0 : cast(int) ceil(s);
        int x0 = cast(int) floor(lx * s) - m;
        int y0 = cast(int) floor(ly * s) - m;
        int x1 = cast(int) floor((lx + lw) * s) + m;
        int y1 = cast(int) floor((ly + lh) * s) + m;
        if (x1 <= x0 || y1 <= y0) return;

        HDC memDc = CreateCompatibleDC(dc);
        if (memDc is null) return;
        scope(exit) DeleteDC(memDc);
        HBITMAP bmp = CreateCompatibleBitmap(dc, x1 - x0, y1 - y0);
        if (bmp is null) return;
        auto old = SelectObject(memDc, bmp);
        BitBlt(memDc, 0, 0, x1 - x0, y1 - y0, dc, x0, y0, SRCCOPY);
        SelectObject(memDc, old);
        strip = OverlayStrip(bmp, x0, y0, x1 - x0, y1 - y0);
    }

    private void overlayFreeStrips()
    {
        foreach (ref strip; ovStrips_)
        {
            if (strip.bmp !is null) DeleteObject(strip.bmp);
            strip = OverlayStrip.init;
        }
    }

    private void overlayDrawCurrentRect()
    {
        overlayFreeStrips();
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        HDC dc = driver !is null ? driver.hdc() : null;
        if (dc !is null && ovW_ > 0 && ovH_ > 0)
        {
            overlaySaveStrip(dc, ovStrips_[0], ovX_, ovY_, ovW_, 1);            // N
            overlaySaveStrip(dc, ovStrips_[1], ovX_, ovY_ + ovH_ - 1, ovW_, 1); // S
            overlaySaveStrip(dc, ovStrips_[2], ovX_, ovY_, 1, ovH_);            // W
            overlaySaveStrip(dc, ovStrips_[3], ovX_ + ovW_ - 1, ovY_, 1, ovH_); // E
        }

        fl_color(white);
        lineStyle(lineSolid);
        overlayDrawRectPrimitive(ovX_, ovY_, ovW_, ovH_);

        fl_color(black);
        lineStyle(lineDot);
        overlayDrawRectPrimitive(ovX_, ovY_, ovW_, ovH_);

        lineStyle(lineSolid);
    }

    private void overlayEraseCurrentRect()
    {
        auto driver = cast(GdiGraphicsDriver) currentDriver;
        HDC dc = driver !is null ? driver.hdc() : null;
        if (dc !is null)
        {
            HDC memDc = CreateCompatibleDC(dc);
            if (memDc !is null)
            {
                foreach (ref strip; ovStrips_)
                {
                    if (strip.bmp is null) continue;
                    auto old = SelectObject(memDc, strip.bmp);
                    BitBlt(dc, strip.x, strip.y, strip.w, strip.h, memDc, 0, 0, SRCCOPY);
                    SelectObject(memDc, old);
                }
                DeleteDC(memDc);
            }
        }
        overlayFreeStrips();
    }

    /// Ported from `fl_overlay_clear()`.
    void overlayClear()
    {
        if (ovW_ > 0)
        {
            overlayEraseCurrentRect();
            ovW_ = 0;
        }
    }

    /// Ported from `fl_overlay_rect()`. Unlike the `version (linux)`
    /// twin above, there's no `drawableSize()`-equivalent clamp to the
    /// window's own bounds here (that one queries via `XGetGeometry()`;
    /// the GDI equivalent would need the owning `HWND`, which isn't
    /// threaded through this call at all) -- every current caller
    /// (`DrawingArea.d`) already clamps its own rectangle to the
    /// widget's bounds before calling this, so it's not a gap that
    /// blocks anything today, just a narrower guarantee than the Linux
    /// side offers a future caller.
    void overlayRect(int x, int y, int w, int h)
    {
        if (ovW_ > 0)
        {
            if (x == ovX_ && y == ovY_ && w == ovW_ && h == ovH_) return;
            overlayEraseCurrentRect();
        }

        if (w < 0) { x += w; w = -w; }
        if (h < 0) { y += h; h = -h; }
        if (w < 1) w = 1;
        if (h < 1) h = 1;

        ovX_ = x; ovY_ = y; ovW_ = w; ovH_ = h;

        overlayDrawCurrentRect();
    }
}

/**
 * Nearest-neighbor-resamples `w`x`h` pixels of `d`-byte-stride `l` (0
 * means `w*|d|`) into a freshly-allocated, tightly-packed (stride
 * `sw*|d|`)
 * `sw`x`sh` buffer. A *negative* `d` means the horizontally-flipped
 * source layout `fl_draw_image()` documents (`buf` points at the first
 * byte of the *last* pixel of its first row, and the pixel pointer
 * steps left; the `|d|` bytes of each pixel are still read forward) --
 * the flip is baked into the returned buffer, which is always in
 * normal left-to-right order with a positive `|d|` stride, so callers
 * must use `|d|`, not `d`, for everything downstream of this call.
 * A negative `l` (the vertical-flip form) needs no equivalent handling
 * -- row arithmetic is already signed. This port's deliberate
 * nearest-neighbor approximation for image scaling -- FLTK's `Fl_Scalable_
 * Graphics_Driver::draw_image_rescale()` does the same job but isn't ported
 * verbatim (its own resampling kernel is tied up with FLTK's
 * `Fl_Draw_Image_Cb` row-at-a-time iteration, which this port's
 * raw-buffer entry points don't need). Only ever called when
 * `(sw,sh) != (w,h)`; callers guard `sw > 0 && sh > 0`. Pulled to
 * module scope (not nested in the `version(linux)` block its callers
 * live in) purely so it gets real headless `unittest` coverage despite
 * being used only from X-drawing code -- same reasoning `blendOverRgb()`
 * right below is split out for.
 */
ubyte[] resampleImageNearest(const(ubyte)* buf, int w, int h, int d, int l, int sw, int sh)
{
    immutable int ad = d < 0 ? -d : d;
    int stride = l ? l : w * ad;
    auto result = new ubyte[sw * sh * ad];
    foreach (dy; 0 .. sh)
    {
        int syi = dy * h / sh;
        if (syi >= h) syi = h - 1;
        const(ubyte)* srcRow = buf + syi * stride;
        size_t dstRowOff = cast(size_t) dy * sw * ad;
        foreach (dx; 0 .. sw)
        {
            int sxi = dx * w / sw;
            if (sxi >= w) sxi = w - 1;
            const(ubyte)* src = srcRow + sxi * d; // signed: d < 0 walks left
            result[dstRowOff + dx * ad .. dstRowOff + dx * ad + ad] = src[0 .. ad];
        }
    }
    return result;
}

unittest
{
    // 2x2 RGB source, upscaled 2x to 4x4: each source pixel should
    // become a solid 2x2 block in the result (nearest-neighbor, no
    // blending).
    ubyte[] src = [
        255, 0, 0,    0, 255, 0, // top row: red, green
        0, 0, 255,    255, 255, 0, // bottom row: blue, yellow
    ];
    auto result = resampleImageNearest(src.ptr, 2, 2, 3, 0, 4, 4);
    assert(result.length == 4 * 4 * 3);

    ubyte[] pixelAt(int x, int y)
    {
        size_t off = (y * 4 + x) * 3;
        return result[off .. off + 3].dup;
    }

    assert(pixelAt(0, 0) == [255, 0, 0]);
    assert(pixelAt(1, 0) == [255, 0, 0]);
    assert(pixelAt(2, 0) == [0, 255, 0]);
    assert(pixelAt(3, 0) == [0, 255, 0]);
    assert(pixelAt(0, 3) == [0, 0, 255]);
    assert(pixelAt(3, 3) == [255, 255, 0]);

    // Downscale 4x4 back to 2x2: each result pixel samples one of the
    // four source quadrants.
    auto down = resampleImageNearest(result.ptr, 4, 4, 3, 0, 2, 2);
    assert(down.length == 2 * 2 * 3);

    // Same size (no-op shape, though callers skip calling this at all
    // when sw==w && sh==h): every pixel should come back unchanged.
    auto same = resampleImageNearest(src.ptr, 2, 2, 3, 0, 2, 2);
    assert(same == src);
}

unittest
{
    // Negative d (the horizontal-flip form fl_draw_image() documents,
    // exercised by test/unittest_images' FLIPH toggle): buf points at
    // the first byte of the *last* pixel of row 0, the pixel pointer
    // steps left, each pixel's own bytes are still read forward. The
    // result comes back tightly packed in normal order with the flip
    // already applied -- and, crucially, sized from |d|: sizing it
    // from a negative d is what produced a real OutOfMemoryError
    // (`new ubyte[sw*sh*-3]` sign-extending to a huge size_t).
    ubyte[] src = [
        255, 0, 0,    0, 255, 0, // top row: red, green
        0, 0, 255,    255, 255, 0, // bottom row: blue, yellow
    ];
    auto flipped = resampleImageNearest(src.ptr + 3, 2, 2, -3, 0, 2, 2);
    assert(flipped.length == 2 * 2 * 3);
    assert(flipped == [
        0, 255, 0,    255, 0, 0, // green, red
        255, 255, 0,  0, 0, 255, // yellow, blue
    ]);

    // Negative d *and* an upscale, the combination that actually
    // crashed: each flipped source pixel becomes a solid 2x2 block.
    auto big = resampleImageNearest(src.ptr + 3, 2, 2, -3, 0, 4, 4);
    assert(big.length == 4 * 4 * 3);
    assert(big[0 .. 3] == [0, 255, 0]);   // top-left is now green
    assert(big[9 .. 12] == [255, 0, 0]);  // top-right is now red
}

/**
 * Blends `w`*`h` pixels of `d`-byte-stride gray+alpha (`d==2`) or RGBA
 * (`d==4`) source data source-over `dst` (a tightly-packed `w*h*3` RGB
 * buffer, mutated in place) -- the pure math half of `alphaBlendImage()`
 * above, split out so it gets real headless `unittest` coverage despite
 * needing a live X display to actually source/sink real pixels. Ported
 * from `Fl_Xlib_Graphics_Driver`'s own `alpha_blend()` inner loop
 * (`src/drivers/Xlib/Fl_Xlib_Graphics_Driver_image.cxx`) -- same
 * three-way `srca==0`/`srca==255`/blend special case, same `srca +=
 * srca>>7` integer-rounding compensation, matching bit-for-bit.
 */
void blendOverRgb(const(ubyte)* buf, int w, int h, int d, int l, ubyte[] dst)
{
    // Negative `d` (the horizontal-flip form, see drawImage()) steps the
    // source pointer left while still reading each pixel's own bytes
    // forward; |d| is what classifies gray+alpha vs. RGBA and sizes the
    // default row stride.
    immutable int ad = d < 0 ? -d : d;
    int lineDelta = l ? l : w * ad;
    size_t dstIdx = 0;

    for (int row = 0; row < h; row++)
    {
        const(ubyte)* p = buf + row * lineDelta;
        for (int col = 0; col < w; col++)
        {
            ubyte srcr, srcg, srcb, srca;
            if (ad == 2) { srcr = srcg = srcb = p[0]; srca = p[1]; }
            else { srcr = p[0]; srcg = p[1]; srcb = p[2]; srca = p[3]; }
            p += d;

            if (srca == 0)
            {
                // "ignore" -- dst already holds the destination pixel,
                // nothing to overwrite.
            }
            else if (srca == 255)
            {
                dst[dstIdx] = srcr;
                dst[dstIdx + 1] = srcg;
                dst[dstIdx + 2] = srcb;
            }
            else
            {
                uint sa = srca + (srca >> 7);
                uint da = 256 - sa;
                dst[dstIdx] = cast(ubyte) ((srcr * sa + dst[dstIdx] * da) >> 8);
                dst[dstIdx + 1] = cast(ubyte) ((srcg * sa + dst[dstIdx + 1] * da) >> 8);
                dst[dstIdx + 2] = cast(ubyte) ((srcb * sa + dst[dstIdx + 2] * da) >> 8);
            }
            dstIdx += 3;
        }
    }
}

unittest
{
    // srca==0: destination pixel passes through unchanged.
    ubyte[] dst = [10, 20, 30];
    const(ubyte)[] src = [255, 0, 0, 0]; // red, fully transparent
    blendOverRgb(src.ptr, 1, 1, 4, 0, dst);
    assert(dst == [10, 20, 30]);
}

unittest
{
    // srca==255: destination pixel is fully replaced ("copy").
    ubyte[] dst = [10, 20, 30];
    const(ubyte)[] src = [200, 100, 50, 255];
    blendOverRgb(src.ptr, 1, 1, 4, 0, dst);
    assert(dst == [200, 100, 50]);
}

unittest
{
    // srca==128 (roughly half): a genuine blend, not a copy or no-op.
    // Verifies the result lands strictly between src and dst on every
    // channel (exact value depends on the srca+=srca>>7 rounding
    // compensation, which this just treats as an implementation
    // detail rather than hand-deriving the precise expected byte).
    ubyte[] dst = [0, 0, 0];
    const(ubyte)[] src = [255, 255, 255, 128];
    blendOverRgb(src.ptr, 1, 1, 4, 0, dst);
    assert(dst[0] > 0 && dst[0] < 255);
    assert(dst[0] == dst[1] && dst[1] == dst[2]);
}

unittest
{
    // d==2 (gray+alpha): the gray value is broadcast to all 3 RGB
    // channels before blending, matching FLTK's own "composite
    // grayscale + alpha over RGB" branch.
    ubyte[] dst = [0, 0, 0];
    const(ubyte)[] src = [200, 255]; // gray=200, fully opaque
    blendOverRgb(src.ptr, 1, 1, 2, 0, dst);
    assert(dst == [200, 200, 200]);
}

unittest
{
    // Explicit row stride (l != w*d) is honored: a 1-pixel-wide image
    // with padding bytes after its one real pixel must still read that
    // pixel correctly, not drift into the padding.
    const(ubyte)[] src = [
        255, 0, 0, 255,  // the one real pixel: opaque red
        0, 0, 0, 0,      // 4 bytes of row padding (l=8, w*d=4)
    ];
    ubyte[] dst = [0, 0, 0];
    blendOverRgb(src.ptr, 1, 1, 4, 8, dst);
    assert(dst == [255, 0, 0]);
}

unittest
{
    // Negative d (the horizontal-flip form -- see drawImage()'s own
    // doc comment): buf points at the first byte of the *last* pixel,
    // the pixel pointer steps left, and the pixel's own 4 bytes are
    // still read forward. Two opaque pixels come out mirrored; |d| is
    // also what picks the RGBA branch over the gray+alpha one.
    const(ubyte)[] src = [
        255, 0, 0, 255, // red
        0, 0, 255, 255, // blue
    ];
    ubyte[] dst = [0, 0, 0, 0, 0, 0];
    blendOverRgb(src.ptr + 4, 2, 1, -4, 0, dst);
    assert(dst == [0, 0, 255, 255, 0, 0]); // blue first, then red
}

unittest
{
    // Negative d with d == -2: still the gray+alpha branch (|d| == 2),
    // not the RGBA one -- classifying off the raw signed d would read
    // src[3] past the end of a 2-byte pixel.
    const(ubyte)[] src = [
        100, 255, // gray 100, opaque
        200, 255, // gray 200, opaque
    ];
    ubyte[] dst = [0, 0, 0, 0, 0, 0];
    blendOverRgb(src.ptr + 2, 2, 1, -2, 0, dst);
    assert(dst == [200, 200, 200, 100, 100, 100]);
}

// ---------------------------------------------------------------------
// Color-spec parsing (backs fl.pixmap's XPM color-table decoding) --
// ported from fl_parse_color()/Fl::screen_driver()->parse_color()
// (src/Fl_get_system_colors.cxx). FLTK forwards this entirely to
// the X11 driver's own XParseColor() call (X server color-name
// database + hex parsing, both in one); this port splits it in two so
// the common case (an explicit "#RRGGBB"-style hex spec, the
// overwhelming majority of real-world XPM files) is a pure, headless-
// testable function, falling back to a real XParseColor() round trip
// only for bare X11 color names (e.g. "red", "steelblue") -- which
// needs a live display, matching every other X-server-dependent
// primitive in this module.

/// Parses one hex digit (0-9, a-f, A-F); returns -1 for anything else.
private int hexDigitValue(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/**
 * Parses an XPM/X11-style hex color body (the part after `#`): 1, 2,
 * 3, or 4 hex digits per channel (3/6/9/12 digits total), each
 * channel scaled to 8 bits by keeping its most significant 8 bits (or
 * left-shifting if it has fewer than 8 bits) -- matching the general
 * X11 hex-color convention `XParseColor()` itself implements. Pure,
 * no display needed -- the real hex-parsing half of `parseColor()`
 * below.
 */
private bool parseHexColor(string s, out ubyte r, out ubyte g, out ubyte b)
{
    if (s.length == 0 || s.length % 3 != 0 || s.length > 12) return false;
    size_t n = s.length / 3; // hex digits per channel
    uint maxVal = (1u << (n * 4)) - 1;
    uint[3] vals;
    foreach (ch; 0 .. 3)
    {
        uint v = 0;
        foreach (c; s[ch * n .. (ch + 1) * n])
        {
            int d = hexDigitValue(c);
            if (d < 0) return false;
            v = (v << 4) | d;
        }
        // Scale an n*4-bit value up to a full 16-bit value, then keep
        // the high byte -- matches XParseColor()'s own "old" numeric
        // color spec scaling exactly (proportional, not a naive left-
        // shift: e.g. "#F00"'s single hex digit 0xF must map to a full
        // 0xFF, not the left-shifted 0xF0).
        uint scaled16 = cast(uint)((cast(ulong) v * 65535) / maxVal);
        vals[ch] = scaled16 >> 8;
    }
    r = cast(ubyte) vals[0];
    g = cast(ubyte) vals[1];
    b = cast(ubyte) vals[2];
    return true;
}

version (linux)
{
    /**
     * Parses a color spec into RGB components -- `#RRGGBB`-style hex
     * (any of the 1/2/3/4-digit-per-channel forms, see
     * parseHexColor()) handled directly, anything else looked up
     * against the X server's own color-name database via a real
     * `XParseColor()` call (needs a live display; returns `false`
     * without one, matching "no image was found" rather than crashing).
     * Ported from `fl_parse_color()` (`Fl::screen_driver()->parse_color()`,
     * `src/Fl_get_system_colors.cxx`).
     */
    bool parseColor(string spec, out ubyte r, out ubyte g, out ubyte b)
    {
        if (spec.length == 0) return false;
        if (spec[0] == '#' && parseHexColor(spec[1 .. $], r, g, b)) return true;
        if (display_ is null) return false;

        import std.string : toStringz;

        XColor exact;
        if (XParseColor(display_, colormap_, spec.toStringz, &exact))
        {
            r = cast(ubyte)(exact.red >> 8);
            g = cast(ubyte)(exact.green >> 8);
            b = cast(ubyte)(exact.blue >> 8);
            return true;
        }
        return false;
    }

    /**
     * Sets a 1-bit clip mask (as created by createBitmask()) around
     * subsequent drawing, positioned so the mask's own (0,0) lands at
     * (originX,originY) -- backs `Fl_Pixmap`'s transparency (binary,
     * not alpha-blended: a classic XPM color is either fully opaque or
     * the one transparent color, so a clip mask is exactly as capable
     * as FLTK's own mechanism here, no compositing needed -- see
     * `fl.pixmap`'s row). Pair with clearClipMask() once done. Ported
     * from the relevant half of
     * `Fl_Xlib_Graphics_Driver::draw_fixed(Fl_Pixmap*,...)`.
     *
     * `originX`/`originY` are FLTK units, scaled via `scaledFloor()`
     * plus `offsetX_`/`offsetY_` here -- **a real bug found via a live
     * user report** ("pixmaps not drawn correctly" at any scale != 1):
     * `fl.pixmap.Pixmap.draw()` calls this with the *un*scaled image
     * origin, then immediately calls `drawImage()`, which scales its
     * *own* destination internally. At
     * `currentScale() == 1` the two happened to agree by coincidence
     * (scaling is a no-op), but at any other scale the mask's origin
     * and the actual blitted pixels disagreed, misaligning the
     * transparency mask from the image data -- exactly matching
     * FLTK's own `Fl_Xlib_Graphics_Driver::draw_fixed(Fl_Pixmap*,...)`
     * scaling its own equivalent origin before this same call. Matching
     * `putPackedImage()`'s exact transform keeps this aligned with
     * wherever `drawImage()` actually draws.
     */
    void setClipMask(ulong maskId, int originX, int originY)
    {
        if (gc_ is null || maskId == 0) return;
        XSetClipMask(display_, gc_, cast(Pixmap) maskId);
        XSetClipOrigin(display_, gc_, scaledFloor(originX) + offsetX_, scaledFloor(originY) + offsetY_);
    }

    /// Restores the GC to this module's own real clip-stack state
    /// (see restoreClip()'s own doc comment) -- pairs with
    /// setClipMask() above.
    void clearClipMask()
    {
        if (gc_ is null) return;
        XSetClipMask(display_, gc_, 0);
        XSetClipOrigin(display_, gc_, 0, 0);
        restoreClip();
    }
}
else
{
    /// No X server to query named colors against on non-Linux
    /// platforms yet -- still handles the hex form for real.
    bool parseColor(string spec, out ubyte r, out ubyte g, out ubyte b)
    {
        if (spec.length == 0 || spec[0] != '#') return false;
        return parseHexColor(spec[1 .. $], r, g, b);
    }

    /// Deliberately still stubs -- dead code on this
    /// platform, same reasoning as `createBitmask()`/`freeBitmask()`'s
    /// own doc comment above: `fl.pixmap.Pixmap.draw()`'s only caller of
    /// these two always takes its `currentDriver !is null` branch first
    /// (real, always installed on Windows) and `return`s before ever
    /// reaching them, drawing real per-pixel RGBA transparency instead
    /// of a binary clip mask. See that comment for the full reasoning.
    void setClipMask(ulong maskId, int originX, int originY) { }
    void clearClipMask() { }
}

unittest
{
    // parseHexColor()/parseColor() hex path: pure, headless-safe.
    ubyte r, g, b;

    assert(parseColor("#FF0000", r, g, b));
    assert(r == 255 && g == 0 && b == 0);

    assert(parseColor("#F00", r, g, b)); // 1 digit/channel, scaled up
    assert(r == 255 && g == 0 && b == 0);

    assert(parseColor("#FF00", r, g, b) == false); // 4 digits: not divisible by 3 channels

    assert(parseColor("#GG0000", r, g, b) == false); // not hex

    assert(parseColor("", r, g, b) == false);
}
