/*
 * Ported from FL/Fl_Paged_Device.H + src/Fl_Paged_Device.cxx
 * (FLTK 1.5.0).
 *
 * Much thinner than its size in `PORTING.md`'s dependency notes might
 * suggest: `Fl_Paged_Device` itself is just `Fl_Widget_Surface` plus
 * the `page_formats[]` table (paper width/height/name for `A0`..`A9`/
 * `B0`..`B10`/executive/folio/ledger/legal/letter/tabloid/envelope) and
 * a handful of virtual methods with trivial "not implemented" default
 * bodies (`beginJob()`/`beginPage()`/`endPage()` return failure,
 * `margins()`/`scale()`/`rotate()`/`endJob()` are no-ops) -- FLTK's
 * own doc comment: "This class has no public constructor: don't
 * instantiate it; use Fl_Printer or Fl_PostScript_File_Device
 * instead." All the real multi-page PostScript-emission logic lives in
 * a real subclass's own overrides, not here. **`fl.postscript.
 * PostscriptFileDevice` is that real subclass now** (added the same
 * day as this module, see `PORTING.md`'s `FL/Fl_PostScript.H` row) --
 * `Fl_Printer` (`FL/Fl_Printer.H`) remains the only unported one,
 * needing its own `print_panel` dialog plus `popen`-based print
 * spooling, neither related to this class.
 *
 * `PagedDevice` is declared `abstract` (no D constructor-visibility
 * trick needed the way `fl.image_surface`/`fl.widget_surface` have
 * used elsewhere -- D's `abstract` keyword blocks direct instantiation
 * of the class by itself, matching FLTK's "don't instantiate this,
 * use a subclass" intent exactly, even though none of its own methods
 * are abstract).
 *
 * `Page_Format`/`Page_Layout` are ported as `alias`-plus-manifest-
 * constants (not real D `enum`s), matching this port's own convention
 * for open sets combined with `|` (see `CONVENTIONS.md`'s "Porting
 * conventions" -- same treatment as `Align`/`Color`/`Font`/`When`/
 * `Damage`): FLTK itself ORs a `Page_Format` value together with a
 * `Page_Layout` value (`Fl_PostScript_File_Device::begin_job()`:
 * `page_format_ = ((int)format | (int)layout)`), and `Page_Format`'s
 * own `MEDIA = 0x1000` member is itself a flag bit meant to be ORed
 * into a `media` parameter alongside `Page_Layout` bits elsewhere
 * (`Fl_PostScript_Graphics_Driver::page()`) -- a real `enum` would
 * force casts back to `int` at every one of those call sites for no
 * benefit.
 */
module fl.paged_device;

import fl.widget_surface : WidgetSurface;
import fl.graphics_driver : GraphicsDriver;
import fl.widget : Widget;
import fl.window : Window;

/// Open bitmask/index set (see this module's own top comment for why
/// this isn't a real D `enum`) -- ported from `Fl_Paged_Device::
/// Page_Format`. Values 0..29 index `pageFormats[]` directly; `media`
/// is a separate flag bit, not a page size.
alias PageFormat = int;

enum : PageFormat
{
    a0 = 0, a1, a2, a3, a4, a5, a6, a7, a8, a9,
    b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10,
    c5e, dle, executive, folio, ledger, legal, letter, tabloid, envelope,
    media = 0x1000,
}

/// Ported from `Fl_Paged_Device::Page_Layout`.
alias PageLayout = int;

enum : PageLayout
{
    portrait = 0,
    landscape = 0x100,
    reversed = 0x200,
    orientation = 0x300,
}

/// Ported from `Fl_Paged_Device::page_format` (the anonymous `typedef
/// struct` -- width/height in points, plus a display name).
struct PageFormatInfo
{
    int width;
    int height;
    string name;
}

/// Ported verbatim from `Fl_Paged_Device::page_formats[NO_PAGE_FORMATS]`
/// (`src/Fl_Paged_Device.cxx`) -- order matches `PageFormat`'s own
/// values exactly (index N is `PageFormat` value N), per FLTK's own
/// "order of enum Page_Format" comment. Widths/heights come from
/// FLTK's own cited source, "appendix B of 5003.PPD_Spec_v4.3.pdf".
static immutable PageFormatInfo[30] pageFormats = [
    PageFormatInfo(2384, 3370, "A0"),
    PageFormatInfo(1684, 2384, "A1"),
    PageFormatInfo(1191, 1684, "A2"),
    PageFormatInfo(842, 1191, "A3"),
    PageFormatInfo(595, 842, "A4"),
    PageFormatInfo(420, 595, "A5"),
    PageFormatInfo(297, 420, "A6"),
    PageFormatInfo(210, 297, "A7"),
    PageFormatInfo(148, 210, "A8"),
    PageFormatInfo(105, 148, "A9"),
    PageFormatInfo(2920, 4127, "B0(JIS)"),
    PageFormatInfo(2064, 2920, "B1(JIS)"),
    PageFormatInfo(1460, 2064, "B2(JIS)"),
    PageFormatInfo(1032, 1460, "B3(JIS)"),
    PageFormatInfo(729, 1032, "B4(JIS)"),
    PageFormatInfo(516, 729, "B5(JIS)"),
    PageFormatInfo(363, 516, "B6(JIS)"),
    PageFormatInfo(258, 363, "B7(JIS)"),
    PageFormatInfo(181, 258, "B8(JIS)"),
    PageFormatInfo(127, 181, "B9(JIS)"),
    PageFormatInfo(91, 127, "B10(JIS)"),
    PageFormatInfo(459, 649, "EnvC5"),
    PageFormatInfo(312, 624, "EnvDL"),
    PageFormatInfo(522, 756, "Executive"),
    PageFormatInfo(595, 935, "Folio"),
    PageFormatInfo(1224, 792, "Ledger"),
    PageFormatInfo(612, 1008, "Legal"),
    PageFormatInfo(612, 792, "Letter"),
    PageFormatInfo(792, 1224, "Tabloid"),
    PageFormatInfo(297, 684, "Env10"),
];

/**
 * Ported from `Fl_Paged_Device` (`FL/Fl_Paged_Device.H` +
 * `src/Fl_Paged_Device.cxx`) -- represents page-structured drawing
 * surfaces. See this module's own top comment: every method here has
 * FLTK's own trivial default body (failure/no-op); a real
 * subclass (`Fl_Printer`/`Fl_PostScript_File_Device`, ported as
 * `fl.printer` and `fl.postscript`) overrides them with real
 * page-emission logic.
 */
abstract class PagedDevice : WidgetSurface
{
    this(GraphicsDriver driver = null)
    {
        super(driver);
    }

    /**
     * Begins a print job. Ported from `Fl_Paged_Device::begin_job()`.
     * `fromPage`/`toPage` are set to the first/last page the user
     * wants printed; `errMessage` to a description of the error if the
     * return value is >= 2. FLTK's own default body always returns
     * `1` (user cancelled) without touching any of the `out` params --
     * matched here exactly (D's `out` parameters are always zero/`null`
     * -initialized by the caller before the call regardless, so a
     * no-op body leaves them at that default, same observable result
     * as FLTK's untouched pointed-to values for a typical
     * zero-initialized caller).
     */
    int beginJob(int pageCount, out int fromPage, out int toPage, out string errMessage)
    {
        return 1;
    }

    /// Ported from `Fl_Paged_Device::begin_page()`.
    int beginPage()
    {
        return 1;
    }

    /// Ported from `Fl_Paged_Device::margins()`.
    void margins(out int left, out int top, out int right, out int bottom)
    {
    }

    /// Ported from `Fl_Paged_Device::scale()`.
    void scale(float scaleX, float scaleY = 0)
    {
    }

    /// Ported from `Fl_Paged_Device::rotate()`.
    void rotate(float angle)
    {
    }

    /// Synonym of `draw(Widget, int, int)`. Ported from
    /// `Fl_Paged_Device::print_widget()`.
    void printWidget(Widget widget, int deltaX = 0, int deltaY = 0)
    {
        draw(widget, deltaX, deltaY);
    }

    /// Synonym of `drawDecoratedWindow(Window, int, int)`. Ported from
    /// `Fl_Paged_Device::print_window()`.
    void printWindow(Window win, int xOff = 0, int yOff = 0)
    {
        drawDecoratedWindow(win, xOff, yOff);
    }

    /// Ported from `Fl_Paged_Device::end_page()`.
    int endPage()
    {
        return 1;
    }

    /// Ported from `Fl_Paged_Device::end_job()`.
    void endJob()
    {
    }
}

unittest
{
    // A real subclass exists (fl.postscript.PostscriptFileDevice --
    // see this module's own top comment), but importing fl.postscript
    // here just to test PagedDevice's own default ("not implemented")
    // bodies would be a pointless module-coupling; a throwaway
    // subclass exercises those, and the page_formats[] table, in
    // complete isolation. PostscriptFileDevice's own unittests (in
    // fl.postscript) cover the real-subclass-override path instead.
    static class TestPagedDevice : PagedDevice
    {
    }

    assert(pageFormats[a4].width == 595 && pageFormats[a4].height == 842);
    assert(pageFormats[a4].name == "A4");
    assert(pageFormats[letter].width == 612 && pageFormats[letter].height == 792);
    assert(pageFormats.length == 30);
    // PageFormat/PageLayout are plain ints specifically so they can be
    // ORed together without a cast, matching FLTK's own
    // `(int)format | (int)layout` -- this is that combination.
    int combined = a4 | landscape;
    assert(combined == (a4 | 0x100));

    auto dev = new TestPagedDevice();
    int fromPage, toPage;
    string errMessage;
    assert(dev.beginJob(0, fromPage, toPage, errMessage) == 1);
    assert(dev.beginPage() == 1);
    assert(dev.endPage() == 1);
    dev.endJob(); // no-op, just confirm it doesn't throw

    int left, top, right, bottom;
    dev.margins(left, top, right, bottom);
    assert(left == 0 && top == 0 && right == 0 && bottom == 0);
}
