/*
 * Ported from FL/Fl_PDF_File_Surface.H, the Linux half of
 * src/drivers/PostScript/Fl_PostScript.cxx (`Fl_PDF_Pango_File_Surface`)
 * and the Windows `Fl_PDF_GDI_File_Surface` in
 * src/drivers/WinAPI/Fl_WinAPI_Printer_Driver.cxx (FLTK 1.5.0).
 *
 * `PdfFileSurface` writes drawing to a PDF document, one page at a time,
 * and is used like `fl.printer.Printer`: `beginJob()` (or
 * `beginDocument()`), then `beginPage()`, drawing, `endPage()` for each
 * page, and `endJob()`.
 * ---
 * auto pdf = new PdfFileSurface();
 * string err;
 * if (pdf.beginDocument("out.pdf", a4, portrait, err) == 0)
 * {
 *     pdf.beginPage();
 *     pdf.printWidget(someWindow);
 *     pdf.endPage();
 *     pdf.endJob();
 * }
 * ---
 *
 * One unit is one point (1/72 inch). Lines and text stay vector
 * graphics, text stays selectable, and images keep their own resolution.
 *
 * - Linux: pages are drawn through `fl.cairo_graphics_driver.
 *   CairoGraphicsDriver` onto a Cairo PDF surface, with text laid out
 *   by Pango. Text is measured with the display's fonts, like everything
 *   else that positions it, and each string is scaled to the width the
 *   display measured, so a printed label fits where it fits on screen.
 * - Windows: pages are drawn with GDI into the "Microsoft Print to PDF"
 *   printer (Windows 10 and later), through `fl.printer_win32.
 *   GdiPagedDevice`, the page handling `fl.printer.Printer` uses.
 *
 * Gap: a Linux build without Cairo (`--no-cairo`) writes no PDF:
 * `beginJob()`/`beginDocument()` return 2 with an error message. The
 * class exists in every build, so a program using it builds everywhere.
 */
module fl.pdf_file_surface;

import fl.paged_device : PagedDevice, PageFormat, PageLayout, pageFormats, a3, a4, a5,
    b4, b5, executive, legal, letter, tabloid, portrait, landscape;
import fl.image_surface : SurfaceDevice;

version (linux)
{
    version (FLDTK_HAVE_CAIRO) version = PdfCairo;
}
version (Windows) version = PdfGdi;
version (PdfCairo) version = PdfOutput;
version (PdfGdi) version = PdfOutput;

version (PdfGdi)
{
    import core.sys.windows.windows;
    import fl.printer_win32 : GdiPagedDevice;
    private alias PdfBase = GdiPagedDevice;

    /// The name of the Windows printer that writes PDF files.
    private enum pdfPrinterName = "Microsoft Print to PDF";

    /// Windows paper codes (`DMPAPER_*`) of the page formats that have
    /// one, by `PageFormat`; 0 for none.
    private immutable short[30] paperCodes = () {
        import fl.paged_device;
        short[30] t;
        t[letter] = 1;
        t[tabloid] = 3;
        t[ledger] = 4;
        t[legal] = 5;
        t[executive] = 7;
        t[a3] = 8;
        t[a4] = 9;
        t[a5] = 11;
        t[b4] = 12;
        t[b5] = 13;
        t[folio] = 14;
        t[envelope] = 20;
        t[dle] = 27;
        t[c5e] = 28;
        t[a2] = 66;
        t[a6] = 70;
        t[b6] = 88;
        return t;
    }();
}
else
    private alias PdfBase = PagedDevice;

version (PdfCairo)
{
    import std.math : PI;
    import fl.cairo_graphics_driver : CairoGraphicsDriver;
    import fl.pango_c_cairo;
    import fl.enumerations : Fontsize;
    import fldraw = fl.draw;

    /// The Cairo graphics driver drawing into a PDF document: one unit
    /// per point, placed on the page by `place()`, with text scaled to
    /// the display's measurements.
    private final class PdfGraphicsDriver : CairoGraphicsDriver
    {
        private cairo_t* pdf_;

        protected override float drawingScale() { return 1; }

        /// Vertex paths arrive in units, which are points here.
        override bool wantsUnscaledVertices() const { return true; }

        override bool resolutionIndependent() const { return true; }

        /// Starts a `w` x `h` point document at `path`. Returns an error
        /// message, or null on success.
        string open(string path, int w, int h)
        {
            import std.string : toStringz, fromStringz;
            import std.format : format;

            cairo_surface_t* cs = cairo_pdf_surface_create(path.toStringz, w, h);
            cairo_status_t status = cairo_surface_status(cs);
            if (status != CAIRO_STATUS_SUCCESS)
            {
                cairo_surface_destroy(cs);
                return format("Error '%s' while attempting to create %s.",
                    cairo_status_to_string(status).fromStringz, path);
            }
            cairo_pdf_surface_restrict_to_version(cs, CAIRO_PDF_VERSION_1_4);
            pdf_ = cairo_create(cs);
            cairo_surface_destroy(cs);
            setCairo(pdf_);
            return null;
        }

        /// Places units on the page: the margins, then the page device's
        /// scale, origin and rotation, then the sum of active
        /// translations.
        void place(int leftMargin, int topMargin, float scaleX, float scaleY,
            int originX, int originY, float angle, int tx, int ty)
        {
            cairo_matrix_t m;
            cairo_matrix_init_translate(&m, leftMargin, topMargin);
            cairo_matrix_scale(&m, scaleX, scaleY);
            cairo_matrix_translate(&m, originX, originY);
            cairo_matrix_rotate(&m, angle * PI / 180);
            cairo_matrix_translate(&m, tx, ty);
            pageMatrix(m);
        }

        /// Finishes the current page.
        void showPage()
        {
            cairo_show_page(pdf_);
        }

        /// Writes out and closes the document. Returns false if writing
        /// failed.
        bool close()
        {
            cairo_surface_t* s = cairo_get_target(pdf_);
            cairo_surface_finish(s);
            bool ok = cairo_surface_status(s) == CAIRO_STATUS_SUCCESS;
            setCairo(null);
            cairo_destroy(pdf_);
            pdf_ = null;
            return ok;
        }

        /// Draws `str` in the current `fl_font()`, scaled so its width
        /// is the width `fl.draw.width()` measures on the display --
        /// FLTK's `Fl_PostScript_Graphics_Driver::transformed_draw()`.
        override void draw(const(char)[] str, int nChars, int x, int y)
        {
            if (nChars <= 0) return;
            if (nChars < str.length) str = str[0 .. nChars];
            Fontsize size = fldraw.fl_size();
            font(fldraw.currentPangoFontName(), size > 0 ? size : 14);
            int pw = layoutWidth(str);
            if (pw <= 0) return;
            double s = fldraw.width(str, cast(int) str.length) / pw * PANGO_SCALE;
            showText(str, x, y, s);
        }
    }
}

/// The page sizes the format dialog of `PdfFileSurface.beginJob()`
/// offers, in menu order.
private immutable PageFormat[] menuFormats = [a3, a4, a5, b4, b5, executive, legal, letter, tabloid];

/// The orientation last chosen in `PdfFileSurface.beginJob()`'s dialog.
private PageLayout lastLayout_ = portrait;

/**
 * Ported from `Fl_PDF_File_Surface`: drawing into a PDF document. See
 * this module's top comment.
 */
class PdfFileSurface : PdfBase
{
    /// Texts of the page format dialog `beginJob()` shows.
    static string formatDialogTitle = "PDF document settings";
    static string formatDialogPageSize = "Page Size:"; /// ditto
    static string formatDialogOrientation = "Orientation:"; /// ditto
    static string formatDialogDefault = "Set as default"; /// ditto

    private string fileName_;

    /// The path of the PDF document, set by `beginJob()`/
    /// `beginDocument()`.
    string pdfFilename() const { return fileName_; }

    /**
     * Prepares to draw to a PDF document the user chooses: a dialog
     * asks for the page size and orientation, then a file chooser for
     * the document's location and name. The page size can be saved as
     * the default for next time.
     * Params:
     *   defaultFileName = the name the file chooser proposes
     *   errMessage = set to a description of the error when 2 is returned
     * Returns: 0 on success, 1 when the user cancelled, 2 on error.
     */
    int beginJob(string defaultFileName, out string errMessage)
    {
        version (PdfOutput)
        {
            import fl.preferences : Preferences, rootCoreUser;
            import fl.native_file_chooser : NativeFileChooser, BrowseType, saveasConfirm;

            auto prefs = new Preferences(rootCoreUser, "fltk.org", "printers");
            string prefFormat;
            prefs.get("PDF/page_size", prefFormat, "A4");
            int rank = 1; // A4
            foreach (i, f; menuFormats)
            {
                if (pageFormats[f].name == prefFormat)
                {
                    rank = cast(int) i;
                    break;
                }
            }
            bool setDefault;
            PageLayout layout = lastLayout_;
            PageFormat format;
            if (!askFormat(rank, format, layout, setDefault)) return 1;
            if (setDefault)
            {
                prefs.set("PDF/page_size", pageFormats[format].name);
                prefs.flush();
            }

            auto chooser = new NativeFileChooser(BrowseType.browseSaveFile);
            chooser.presetFile(defaultFileName);
            chooser.filter("PDF\t*.pdf\n");
            chooser.options(saveasConfirm);
            int r = chooser.show();
            if (r == -1)
            {
                errMessage = chooser.errmsg();
                return 2;
            }
            if (r != 0 || chooser.filename().length == 0) return 1;

            lastLayout_ = layout;
            return beginDocument(chooser.filename(), format, layout, errMessage);
        }
        else
        {
            errMessage = "PDF output needs fldtk built with Cairo.";
            return 2;
        }
    }

    /// ditto
    int beginJob(string defaultFileName)
    {
        string errMessage;
        return beginJob(defaultFileName, errMessage);
    }

    /// Not for this class: use `beginJob(string)` or `beginDocument()`.
    override int beginJob(int pageCount, out int fromPage, out int toPage, out string errMessage)
    {
        return 1;
    }

    /**
     * Prepares to draw to the PDF document at `path`, with pages of
     * `format` in `layout` orientation.
     * Params:
     *   errMessage = set to a description of the error when 2 is returned
     * Returns: 0 on success, 2 on error.
     */
    int beginDocument(string path, PageFormat format, PageLayout layout, out string errMessage)
    {
        endJob();
        version (PdfCairo)
        {
            int w = pageFormats[format].width;
            int h = pageFormats[format].height;
            if (layout & landscape)
            {
                int t = w;
                w = h;
                h = t;
            }
            errMessage = pdfDriver().open(path, w, h);
            if (errMessage !is null) return 2;
            pw_ = w;
            ph_ = h;
            leftMargin_ = topMargin_ = format == a4 ? 18 : 12;
            open_ = true;
        }
        else version (PdfGdi)
        {
            import std.utf : toUTF16z;
            import std.format : format_ = format;

            DEVMODEW dm;
            dm.dmSize = DEVMODEW.sizeof;
            dm.dmOrientation = layout & landscape ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT;
            dm.dmFields = DM_ORIENTATION;
            short code = format >= 0 && format < paperCodes.length ? paperCodes[format] : 0;
            if (code)
            {
                dm.dmPaperSize = code;
                dm.dmFields |= DM_PAPERSIZE;
            }
            else
            {
                // tenths of a millimetre
                dm.dmPaperWidth = cast(short)(pageFormats[format].width * 254 / 72);
                dm.dmPaperLength = cast(short)(pageFormats[format].height * 254 / 72);
                dm.dmFields |= DM_PAPERWIDTH | DM_PAPERLENGTH;
            }
            HDC dc = CreateDCW(null, pdfPrinterName, null, &dm);
            if (dc is null)
            {
                errMessage = "PDF output needs the printer '" ~ pdfPrinterName
                    ~ "' (Windows 10 and later).";
                return 2;
            }
            DOCINFOW di;
            di.cbSize = DOCINFOW.sizeof;
            di.lpszDocName = "FLTK";
            di.lpszOutput = toUTF16z(path);
            if (StartDocW(dc, &di) <= 0)
            {
                DWORD dw = GetLastError();
                DeleteDC(dc);
                errMessage = format_("Error %d in StartDoc() call", dw);
                return 2;
            }
            startOutput(dc);
        }
        else
        {
            errMessage = "PDF output needs fldtk built with Cairo.";
            return 2;
        }
        fileName_ = path;
        return 0;
    }

    /// ditto
    int beginDocument(string path, PageFormat format = a4, PageLayout layout = portrait)
    {
        string errMessage;
        return beginDocument(path, format, layout, errMessage);
    }

    version (PdfGdi) { } else
    {

    private bool open_;
    private int pw_, ph_;
    private int leftMargin_, topMargin_;
    private float scaleX_ = 1, scaleY_ = 1;
    private float angle_ = 0;
    private int[2][] translations_;

    this()
    {
        version (PdfCairo) super(new PdfGraphicsDriver());
        else super(null);
    }

    ~this()
    {
        import core.memory : GC;
        if (GC.inFinalizer()) return;
        if (open_) endJob();
    }

    /// Ported from `margins()`: the page margins, in the current scale's
    /// units.
    override void margins(out int left, out int top, out int right, out int bottom)
    {
        left = right = cast(int)(leftMargin_ / scaleX_ + .5);
        top = bottom = cast(int)(topMargin_ / scaleY_ + .5);
    }

    /// Ported from `printable_rect()`: the page inside its margins, in
    /// the current scale's units.
    override int printableRect(out int w, out int h) const
    {
        w = cast(int)((pw_ - 2 * leftMargin_) / scaleX_ + .5);
        h = cast(int)((ph_ - 2 * topMargin_) / scaleY_ + .5);
        return 0;
    }

    /// Ported from `origin(int, int)`: puts the drawing origin at
    /// `(x, y)` of the printable area, in the current scale's units.
    override void origin(int x, int y)
    {
        super.origin(x, y);
        place();
    }

    /// Ported from `scale()`: scales drawing by `scaleX` horizontally
    /// and `scaleY` vertically (`scaleX` both ways when `scaleY` is 0).
    /// The origin goes back to the top left corner of the printable
    /// area, so call `origin()` after `scale()`.
    override void scale(float scaleX, float scaleY = 0)
    {
        if (scaleY == 0) scaleY = scaleX;
        scaleX_ = scaleX;
        scaleY_ = scaleY;
        xOffset_ = yOffset_ = 0;
        place();
    }

    /// Ported from `rotate()`: rotates drawing `angle` degrees
    /// counter-clockwise about the origin. Successive calls don't add up.
    override void rotate(float angle)
    {
        angle_ = -angle;
        place();
    }

    protected override void translate(int x, int y)
    {
        translations_ ~= [x, y];
        place();
    }

    protected override void untranslate()
    {
        if (translations_.length == 0) return;
        translations_ = translations_[0 .. $ - 1];
        place();
    }

    /// Ported from `begin_page()`: starts a page and makes this surface
    /// the current drawing surface, with the origin at the top left
    /// corner of the printable area, no scaling and no rotation.
    /// Returns 1 when no document is open.
    override int beginPage()
    {
        if (!open_) return 1;
        SurfaceDevice.pushCurrent(this);
        xOffset_ = yOffset_ = 0;
        scaleX_ = scaleY_ = 1;
        angle_ = 0;
        translations_ = null;
        place();
        return 0;
    }

    /// Ported from `end_page()`: finishes the page and stops this
    /// surface from being the current drawing surface.
    override int endPage()
    {
        if (!open_) return 1;
        version (PdfCairo) pdfDriver().showPage();
        SurfaceDevice.popCurrent();
        return 0;
    }

    /// Ported from `end_job()`: writes out and closes the document.
    /// Shows an alert if writing failed.
    override void endJob()
    {
        if (!open_) return;
        open_ = false;
        version (PdfCairo)
        {
            if (!pdfDriver().close())
            {
                import fl.ask : alert;
                alert("Error while writing " ~ fileName_ ~ ".");
            }
        }
    }

    private void place()
    {
        version (PdfCairo)
        {
            int tx = 0, ty = 0;
            foreach (t; translations_)
            {
                tx += t[0];
                ty += t[1];
            }
            pdfDriver().place(leftMargin_, topMargin_, scaleX_, scaleY_, xOffset_, yOffset_, angle_, tx, ty);
        }
    }

    version (PdfCairo)
    {
        private PdfGraphicsDriver pdfDriver() { return cast(PdfGraphicsDriver) driver(); }
    }
    }
}

version (PdfOutput)
{
    /// The page format dialog of `PdfFileSurface.beginJob()` -- FLTK's
    /// `update_format_layout()`. `rank` is the `menuFormats` entry
    /// selected first. Returns false when cancelled.
    private bool askFormat(int rank, out PageFormat format, ref PageLayout layout, out bool setDefault)
    {
        import fl.window : Window;
        import fl.choice : Choice;
        import fl.check_button : CheckButton;
        import fl.return_button : ReturnButton;
        import fl.button : Button;
        import fl.enumerations : whenChanged;
        import fl.ask : ok, fl_cancel;
        import fl.core : wait;

        bool accepted = false;
        auto modal = new Window(510, 90, PdfFileSurface.formatDialogTitle);
        auto psize = new Choice(140, 10, 110, 30, PdfFileSurface.formatDialogPageSize);
        psize.when(whenChanged);
        foreach (f; menuFormats) psize.add(pageFormats[f].name, 0, null);
        psize.value(rank);
        auto defaultSize = new CheckButton(psize.x(), psize.y() + psize.h(), psize.w(), psize.h(),
            PdfFileSurface.formatDialogDefault);
        defaultSize.value(1);
        psize.callback((w) {
            // choosing another size unticks "Set as default"
            if (defaultSize.value() && psize.mvalue() !is null && psize.prevMvalue() !is null
                && psize.prevMvalue() !is psize.mvalue())
                defaultSize.value(0);
        });
        auto orientation = new Choice(psize.x() + psize.w() + 120, psize.y(), 130, psize.h(),
            PdfFileSurface.formatDialogOrientation);
        orientation.add("PORTRAIT", 0, null);
        orientation.add("LANDSCAPE", 0, null);
        orientation.value(layout & landscape ? 1 : 0);
        auto okButton = new ReturnButton(orientation.x() + orientation.w() - 55,
            psize.y() + psize.h() + 10, 55, 30, ok);
        okButton.callback((w) {
            accepted = true;
            modal.hide();
        });
        auto cancel = new Button(okButton.x() - 90, psize.y() + psize.h() + 10, 70, 30, fl_cancel);
        cancel.callback((w) { modal.hide(); });
        modal.end();
        modal.setModal();
        modal.show();
        while (modal.shown()) wait();
        if (accepted)
        {
            format = menuFormats[psize.value()];
            layout = orientation.value() == 1 ? landscape : portrait;
            setDefault = defaultSize.value() != 0;
        }
        import fl.core : deleteWidget;
        deleteWidget(modal);
        return accepted;
    }
}

// Not on Windows, where writing a document goes through the system's
// "Microsoft Print to PDF" printer.
version (PdfGdi) { } else
unittest
{
    import std.file : tempDir, exists, remove, read;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind;
    import fl.enumerations : black, red;
    import fldraw = fl.draw;

    auto path = buildPath(tempDir(), "fldtk-pdf-test-" ~ randomUUID().toString() ~ ".pdf");
    scope (exit) if (exists(path)) remove(path);

    auto pdf = new PdfFileSurface();
    string err;
    int r = pdf.beginDocument(path, a4, landscape, err);
    version (PdfCairo)
    {
        assert(r == 0, err);
        assert(pdf.pdfFilename() == path);
        int w, h;
        pdf.printableRect(w, h);
        assert(w == 842 - 36 && h == 595 - 36);
        pdf.scale(0.5);
        pdf.printableRect(w, h);
        assert(w == 2 * (842 - 36));

        import fl.core : currentScale;
        float screenScale = currentScale();
        currentScale(2); // a page's images ignore the screen scale
        scope (exit) currentScale(screenScale);
        foreach (page; 0 .. 2)
        {
            assert(pdf.beginPage() == 0);
            assert(fldraw.imageScale() == 1);
            fldraw.fl_color(red);
            fldraw.fl_rectf(10, 10, 100, 50);
            fldraw.fl_color(black);
            fldraw.fl_line(0, 0, 200, 100);
            pdf.rotate(30);
            fldraw.fl_rect(20, 20, 60, 30);
            assert(pdf.endPage() == 0);
        }
        pdf.endJob();

        auto data = cast(const(char)[]) read(path);
        assert(data.length > 5 && data[0 .. 5] == "%PDF-");
        assert(data.canFind("/Count 2"));
        assert(data.canFind("%%EOF"));
        assert(pdf.beginPage() == 1); // closed
    }
    else
    {
        assert(r == 2 && err.length);
        assert(!exists(path));
    }
}

