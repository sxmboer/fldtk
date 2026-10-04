/*
 * Ported from FL/Fl_Printer.H + src/drivers/WinAPI/Fl_WinAPI_Printer_
 * Driver.cxx (FLTK 1.5.0, ~/Repositories/fltk) -- the Windows half of
 * `fl.printer`'s platform split (see that module's own doc comment for
 * why the split exists).
 *
 * Without this module, `fl.printer`'s dialog only ports
 * `Fl_Posix_Printer_Driver` (shelling out to
 * `lpstat`/`lpr`/`/etc/printcap`, none of which
 * exist on Windows) -- its printer dropdown would never find any
 * installed Windows printer, only ever offering "Print To File". See
 * `PORTING.md`'s `FL/Fl_Printer.H` row for the overview.
 *
 * Real FLTK Windows printing is a completely different, unrelated
 * mechanism from the POSIX half (`fl.printer_posix`): a native
 * `PRINTDLG`/`PrintDlg()` common dialog (Windows' own OS-provided
 * printer picker, which lists installed printers by querying the OS
 * print spooler directly -- no shell commands, no FLTK-drawn dialog of
 * any kind, so this module has no `PrintPanel`-equivalent at all),
 * `StartDoc()`/`StartPage()`/`EndPage()`/`EndDoc()` (`wingdi.h`, not
 * `winspool.h` -- these are GDI-level job/page lifecycle calls, distinct
 * from the printer-spooler-level `StartDocPrinter()` family this module
 * never needs) for job lifecycle instead of piping PostScript to a
 * subprocess, and plain GDI drawing straight into the printer's own
 * `HDC` via this port's existing `fl.gdi_graphics_driver.
 * GdiGraphicsDriver` -- not PostScript text at all.
 *
 * `Printer` extends `fl.paged_device.PagedDevice` directly (not
 * `fl.postscript.PostscriptFileDevice`, unlike the POSIX half) --
 * matching FLTK's own `Fl_WinAPI_Printer_Driver : public
 * Fl_Paged_Device` exactly, since nothing here is PostScript-shaped.
 * `WIN_SetupPrinterDeviceContext()` configures the printer HDC for
 * point-unit coordinates (`SetMapMode(MM_ANISOTROPIC)` + matched
 * `SetWindowExtEx()`/`SetViewportExtEx()` so 720 logical units span the
 * physical page's real 10-inch reference size, `SetGraphicsMode(GM_
 * ADVANCED)` to allow rotation) -- ported as `setupPrinterDeviceContext()`.
 *
 * **Deliberately not ported**: `Fl_PDF_GDI_File_Surface` (FLTK's
 * `Fl_PDF_File_Surface` backing implementation, using Windows' own
 * "Microsoft Print to PDF" virtual printer) -- `fl.pdf_file_surface`
 * itself is `Deferred` project-wide (see `CLAUDE.md`'s Pango note and
 * `PORTING.md`'s `FL/Fl_PDF_File_Surface.H` row), so there is no PDF
 * surface class here for it to back. Revisit together with that
 * decision, not before.
 *
 * **Deliberately simplified from FLTK's own `Fl_GDI_Printer_
 * Graphics_Driver`**: FLTK gives printing a *second*, dedicated
 * `Fl_GDI_Graphics_Driver` subclass overriding `draw_pixmap()`/
 * `draw_bitmap()`/`draw_rgb()` to use `TransparentBlt()`-based
 * transparency handling and a world-transform-scaled blit, since many
 * real printer drivers don't rasterize a plain `BitBlt()` the same way a
 * screen HDC does. This module reuses the plain, already-real
 * `fl.gdi_graphics_driver.GdiGraphicsDriver` unchanged (a fresh instance
 * per `Printer`, exactly like FLTK's own fresh-instance-per-job
 * `driver(new Fl_GDI_Printer_Graphics_Driver)`) -- text, rects, lines,
 * polygons, arcs, and clipping all draw identically on a printer HDC via
 * plain GDI calls, so the bulk of this driver needed zero printer-
 * specific code. `test/device`'s RGBA image, pixmap and bitmap print
 * with correct transparency and size this way (Microsoft Print to PDF).
 *
 * The image-transparency gap here is narrow, not total. `GdiGraphicsDriver.
 * drawImage()` has a real dithered-mask fallback
 * (`drawImageDitheredMask()`, ported from `Fl_GDI_Graphics_Driver::
 * create_alphamask()` plus its masked-blit consumer) for exactly the
 * case a printer is most likely to hit: a printer driver whose own DDI
 * doesn't implement `AlphaBlend()` at all -- caught via a real per-call
 * check of `AlphaBlend()`'s own return value against the printer's
 * actual `HDC` (`drawImageAlphaBlended()`'s own doc comment), not the
 * coarse, one-time, screen-only `canDoAlphaBlending()` gate, which
 * can't see a printer-specific failure on its own. That fallback is a genuine,
 * if coarser (screen-door dithered, not smoothly blended), real
 * per-pixel transparency, not a flat, fully-opaque blend.
 * What's still not ported is FLTK's *other* reason
 * for a dedicated printer driver subclass: `Fl_Bitmap`/`Fl_Pixmap`
 * printing still uses this port's plain on-screen `drawBitmap()` body
 * (the standard, documented two-pass AND/OR `StretchBlt()` technique,
 * not FLTK's own printer-specific `TransparentBlt()` swap) --
 * narrower risk than FLTK's own motivation for that override
 * implies, since fldtk's `drawBitmap()` already avoids the undocumented
 * "secret" ternary ROP code FLTK's own *on-screen* driver uses (the
 * actual reliability problem `TransparentBlt()` exists to route around),
 * so there's no known-fragile raster op here to replace in the first
 * place. Revisit if a real bug is reported; nothing in this port's
 * sample tree (`pixmap_browser`/`DrawingArea`/`cube`/`device`) prints a
 * transparent image today.
 */
module fl.printer_win32;

version (Windows):

import core.sys.windows.windows;
import std.format : format;
import std.math : cos, sin, PI;
import std.utf : toUTF8;

import fl.paged_device : PagedDevice;
import fl.image_surface : SurfaceDevice;
import fl.gdi_graphics_driver : GdiGraphicsDriver;
import fl.ask : alert;
import fldraw = fl.draw;

/**
 * OS-independent print support, Windows half. See `fl.printer_posix.
 * Printer` (built on non-Windows platforms instead) for the X11/Wayland
 * half, and `fl.printer`'s own doc comment for the dispatch that picks
 * one or the other. Usage is identical either way -- see `fl.printer_
 * posix.Printer`'s own doc comment for the shared example.
 */
class Printer : PagedDevice
{
    private GdiGraphicsDriver gdiDriver_;

    /// Ported from `Fl_WinAPI_Printer_Driver::pd` -- the common dialog's
    /// own in/out state (selected printer, `DEVMODE`/`DEVNAMES` handles,
    /// page range, ...). Zero-initialized via `PRINTDLGA`'s own default
    /// field initializers (`lStructSize`), matching FLTK's `memset
    /// (&pd, 0, sizeof(PRINTDLG))` + explicit `lStructSize` assignment.
    private PRINTDLGA pd_;

    /// Ported from `Fl_WinAPI_Printer_Driver::hPr` -- `null` when no job
    /// is open.
    private HDC hPr_;

    /// Ported from `Fl_WinAPI_Printer_Driver::abortPrint`.
    private bool abortPrint_;

    /// Ported from `Fl_WinAPI_Printer_Driver::left_margin`/`top_margin`.
    private int leftMargin_, topMargin_;

    /// Cached result of the last `updatePrintableGeometry()` call, read
    /// by `printableRect()`. **Deliberate deviation from FLTK**:
    /// `Fl_WinAPI_Printer_Driver::printable_rect()` recomputes (with
    /// real side effects -- it resets the HDC's window origin every
    /// single call) straight from `absolute_printable_rect()` on *every*
    /// call, which would make `printableRect()` a mutating operation --
    /// impossible to reconcile with `fl.widget_surface.WidgetSurface.
    /// printableRect()`'s own `const` signature (every other subclass's
    /// override is a pure read, so the base method is declared `const`).
    /// Since the paper size/DPI genuinely can't change mid-job, and
    /// every real caller in this port's own sample tree
    /// (`pixmap_browser`/`DrawingArea`/`cube`) calls `printableRect()`
    /// immediately after `beginPage()` and never mutates the origin in
    /// between, computing this once per page (`beginPage()`) or per
    /// `scale()` call and serving cached values from the `const` getter
    /// is behaviorally identical for every real caller, without fighting
    /// the type system for a side effect nothing observes.
    private int cachedW_, cachedH_;

    /// Ported from the file-scope `static int translate_stack_depth`/
    /// `translate_stack_x`/`translate_stack_y` (`Fl_WinAPI_Printer_
    /// Driver.cxx`). **Deliberate deviation from FLTK**: those are
    /// process-wide statics there (shared across every `Fl_Printer`
    /// instance, a real FLTK oddity -- only one print job is ever
    /// realistically active at a time, so it never bites in practice),
    /// kept here as ordinary per-instance fields instead, which is
    /// strictly more correct with no behavioral cost for the single-job
    /// case FLTK itself only ever exercises.
    private enum translateStackMax = 5;
    private int translateStackDepth_;
    private int[translateStackMax] translateStackX_;
    private int[translateStackMax] translateStackY_;

    this()
    {
        auto driver = new GdiGraphicsDriver();
        driver.useFixedScale(1.0);
        super(driver);
        gdiDriver_ = driver;
    }

    /// Ported from `~Fl_WinAPI_Printer_Driver()`.
    ~this()
    {
        if (hPr_ !is null) endJob();
    }

    /// Ported from `WIN_SetupPrinterDeviceContext()` (a file-scope
    /// static function FLTK, not a method) -- sets up point-unit
    /// (1/72 inch) logical coordinates on `dc`. Called at the start of
    /// every page, matching FLTK exactly (`begin_page()` re-applies
    /// it every time, not just once per job).
    private static void setupPrinterDeviceContext(HDC dc)
    {
        if (dc is null) return;
        SetGraphicsMode(dc, GM_ADVANCED);
        SetMapMode(dc, MM_ANISOTROPIC);
        SetTextAlign(dc, TA_BASELINE | TA_LEFT);
        SetBkMode(dc, TRANSPARENT);
        SetWindowExtEx(dc, 720, 720, null);
        SetViewportExtEx(dc, 10 * GetDeviceCaps(dc, LOGPIXELSX),
            10 * GetDeviceCaps(dc, LOGPIXELSY), null);
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::absolute_printable_rect()`
    /// -- see `cachedW_`/`cachedH_`'s own doc comment for why this is a
    /// named, explicitly-triggered recomputation here rather than a
    /// silent side effect of every `printableRect()` call the way
    /// FLTK has it.
    private void updatePrintableGeometry()
    {
        if (hPr_ is null) return;
        HDC gc = hPr_;
        XFORM oldTransform;
        GetWorldTransform(gc, &oldTransform);
        ModifyWorldTransform(gc, null, MWT_IDENTITY);
        SetWindowOrgEx(gc, 0, 0, null);

        POINT physPageSize;
        physPageSize.x = GetDeviceCaps(hPr_, HORZRES);
        physPageSize.y = GetDeviceCaps(hPr_, VERTRES);
        DPtoLP(hPr_, &physPageSize, 1);
        int w = physPageSize.x + 1;
        int h = physPageSize.y + 1;

        POINT pixelsPerInch;
        pixelsPerInch.x = GetDeviceCaps(hPr_, LOGPIXELSX);
        pixelsPerInch.y = GetDeviceCaps(hPr_, LOGPIXELSY);
        DPtoLP(hPr_, &pixelsPerInch, 1);
        leftMargin_ = pixelsPerInch.x / 4;
        w -= pixelsPerInch.x / 2;
        topMargin_ = pixelsPerInch.y / 4;
        h -= pixelsPerInch.y / 2;

        cachedW_ = w;
        cachedH_ = h;

        origin(xOffset_, yOffset_);
        SetWorldTransform(gc, &oldTransform);
    }

    /// Convenience overload for callers that don't need the resulting
    /// page range back -- see `fl.printer_posix.Printer.beginJob()`'s
    /// identical overload for why this exists.
    int beginJob(int pageCount, out string errMessage)
    {
        int fromPage, toPage;
        return beginJob(pageCount, fromPage, toPage, errMessage);
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::begin_job()`. Runs the
    /// native `PrintDlg()` common dialog -- this is what lists every
    /// printer Windows itself knows about, fixing the reported "no
    /// printers found" bug (see this module's own top comment): unlike
    /// the POSIX half, there's no FLTK-drawn dialog here at all to have
    /// gotten out of sync with the OS.
    override int beginJob(int pageCount, out int fromPage, out int toPage,
        out string errMessage)
    {
        if (pageCount == 0) pageCount = 10000;
        abortPrint_ = false;
        pd_ = PRINTDLGA.init;
        pd_.hwndOwner = GetForegroundWindow();
        pd_.Flags = PD_RETURNDC | PD_USEDEVMODECOPIESANDCOLLATE | PD_NOSELECTION;
        pd_.nMinPage = 1;
        pd_.nMaxPage = cast(WORD)(pageCount > ushort.max ? ushort.max : pageCount);

        BOOL ok = PrintDlgA(&pd_);
        if (pd_.hwndOwner)
        {
            // Restores the correct state of mouse buttons/keyboard
            // modifier keys after the dialog closes -- ported from
            // FLTK's own "STR #3221" fix.
            auto windproc = cast(WNDPROC) GetWindowLongPtrW(pd_.hwndOwner, GWLP_WNDPROC);
            if (windproc !is null)
                CallWindowProcW(windproc, pd_.hwndOwner, WM_ACTIVATEAPP, 1, 0);
        }

        int err = 0;
        if (ok != 0)
        {
            hPr_ = pd_.hDC;
            if (hPr_ !is null)
            {
                DOCINFOA di;
                di.lpszDocName = "FLTK";
                int prerr = StartDocA(hPr_, &di);
                if (prerr < 1)
                {
                    abortPrint_ = true;
                    DWORD dw = GetLastError();
                    err = (dw == ERROR_CANCELLED) ? 1 : 2;
                    if (err == 2) errMessage = formatLastError(dw, "begin_job()");
                }
            }
        }
        else
        {
            err = 1;
        }

        if (!err)
        {
            if ((pd_.Flags & PD_PAGENUMS) != 0)
            {
                fromPage = pd_.nFromPage;
                toPage = pd_.nToPage;
            }
            else
            {
                fromPage = 1;
                toPage = pageCount;
            }
            xOffset_ = 0;
            yOffset_ = 0;
            setupPrinterDeviceContext(hPr_);
            gdiDriver_.setHdc(hPr_);
        }
        return err;
    }

    /// Builds the same `"<call>() failed with error <n>: <system
    /// message>"` string FLTK's own `FormatMessageW()` call produces
    /// -- shared by `beginJob()`/`endJob()` (FLTK duplicates a
    /// smaller version of this inline in `begin_job()` only; `end_job()`
    /// just calls `fl_alert("EndDoc error %d", prerr)` without a system
    /// message, ported faithfully as-is in `endJob()` below, so this
    /// helper exists for `beginJob()`'s own richer error path).
    private static string formatLastError(DWORD dw, string what)
    {
        wchar* lpMsgBuf;
        DWORD retval = FormatMessageW(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
                | FORMAT_MESSAGE_IGNORE_INSERTS,
            null, dw, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
            cast(LPWSTR)&lpMsgBuf, 0, null);
        if (retval == 0) return format("%s() failed with error %d", what, dw);
        scope (exit) LocalFree(cast(HLOCAL) lpMsgBuf);
        size_t srclen = cast(size_t) lstrlenW(lpMsgBuf);
        while (srclen > 0 && (lpMsgBuf[srclen - 1] == '\n' || lpMsgBuf[srclen - 1] == '\r'))
            srclen--;
        return format("%s() failed with error %d: %s", what, dw, toUTF8(lpMsgBuf[0 .. srclen]));
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::begin_page()`.
    override int beginPage()
    {
        if (hPr_ is null) return 1;
        SurfaceDevice.pushCurrent(this);
        setupPrinterDeviceContext(hPr_);
        int prerr = StartPage(hPr_);
        if (prerr < 0)
        {
            SurfaceDevice.popCurrent();
            alert(format("StartPage error %d", prerr));
            return 1;
        }
        updatePrintableGeometry();
        origin(0, 0);
        // Ported from FLTK's own `fl_clip_region(0)` here -- see
        // `fl.draw.resetClipStack()`'s own doc comment for why this
        // port's shared, module-level clip stack means this reset isn't
        // quite the near-no-op it is for FLTK (a fresh per-job
        // driver there already starts with its own empty clip stack).
        // A real, low-risk gap on its own; not, on its own, the cause of
        // the actual GDI-clip-region unit bug traced to `fl.gdi_graphics_
        // driver.d`'s `pushClip()` (see `PORTING.md`'s `FL/Fl_Printer.H`
        // row for that one).
        fldraw.resetClipStack();
        return 0;
    }

    protected override void doSetCurrent()
    {
        gdiDriver_.setHdc(hPr_);
    }

    protected override void doEndCurrent()
    {
        gdiDriver_.setHdc(null);
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::margins()`. `right`/
    /// `bottom` really do come out equal to `left`/`top` FLTK too
    /// (both margins are the same quarter-inch value, already baked
    /// into the width/height reduction `updatePrintableGeometry()`
    /// performs) -- not a transliteration bug.
    override void margins(out int left, out int top, out int right, out int bottom)
    {
        updatePrintableGeometry();
        left = leftMargin_;
        top = topMargin_;
        right = leftMargin_;
        bottom = topMargin_;
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::printable_rect()` -- see
    /// `cachedW_`/`cachedH_`'s own doc comment for the one deliberate
    /// deviation (a pure read here, not a fresh recompute-with-side-
    /// effects on every call).
    override int printableRect(out int w, out int h) const
    {
        w = cachedW_;
        h = cachedH_;
        return 0;
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::origin(int, int)`.
    override void origin(int x, int y)
    {
        if (hPr_ !is null)
            SetWindowOrgEx(hPr_, -leftMargin_ - x, -topMargin_ - y, null);
        xOffset_ = x;
        yOffset_ = y;
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::scale()`.
    override void scale(float scaleX, float scaleY = 0)
    {
        if (scaleY == 0) scaleY = scaleX;
        if (hPr_ !is null)
            SetWindowExtEx(hPr_, cast(int)(720 / scaleX + 0.5),
                cast(int)(720 / scaleY + 0.5), null);
        updatePrintableGeometry();
        origin(0, 0);
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::rotate()`.
    override void rotate(float angle)
    {
        if (hPr_ is null) return;
        XFORM mat;
        float rad = -(angle * PI / 180.0);
        mat.eM11 = cast(FLOAT) cos(rad);
        mat.eM12 = cast(FLOAT) sin(rad);
        mat.eM21 = -mat.eM12;
        mat.eM22 = mat.eM11;
        mat.eDx = mat.eDy = 0;
        SetWorldTransform(hPr_, &mat);
    }

    private void doTranslate(int x, int y)
    {
        if (hPr_ is null) return;
        XFORM tr;
        tr.eM11 = tr.eM22 = 1;
        tr.eM12 = tr.eM21 = 0;
        tr.eDx = cast(FLOAT) x;
        tr.eDy = cast(FLOAT) y;
        ModifyWorldTransform(hPr_, &tr, MWT_LEFTMULTIPLY);
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::translate()`.
    protected override void translate(int x, int y)
    {
        doTranslate(x, y);
        if (translateStackDepth_ < translateStackMax)
        {
            translateStackX_[translateStackDepth_] = x;
            translateStackY_[translateStackDepth_] = y;
            translateStackDepth_++;
        }
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::untranslate()`.
    protected override void untranslate()
    {
        if (translateStackDepth_ > 0)
        {
            translateStackDepth_--;
            doTranslate(-translateStackX_[translateStackDepth_], -translateStackY_[translateStackDepth_]);
        }
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::end_page()`.
    override int endPage()
    {
        if (hPr_ is null) return 0;
        SurfaceDevice.popCurrent();
        int prerr = EndPage(hPr_);
        if (prerr < 0)
        {
            abortPrint_ = true;
            alert(format("EndPage error %d", prerr));
            return 1;
        }
        // Keeps rotation from carrying over onto the next page.
        ModifyWorldTransform(hPr_, null, MWT_IDENTITY);
        return 0;
    }

    /// Ported from `Fl_WinAPI_Printer_Driver::end_job()`.
    override void endJob()
    {
        if (hPr_ !is null)
        {
            if (!abortPrint_)
            {
                int prerr = EndDoc(hPr_);
                if (prerr < 0) alert(format("EndDoc error %d", prerr));
            }
            DeleteDC(hPr_);
            if (pd_.hDevMode !is null) GlobalFree(pd_.hDevMode);
            if (pd_.hDevNames !is null) GlobalFree(pd_.hDevNames);
        }
        hPr_ = null;
    }
}
