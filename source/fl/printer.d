/*
 * `Fl_Printer` (`FL/Fl_Printer.H`, FLTK 1.5.0) -- platform dispatcher
 * only. FLTK's own `Fl_Printer::newPrinterDriver()` returns a
 * completely different concrete driver per platform (`Fl_Posix_Printer_
 * Driver` on X11/Wayland -- a `Fl_PostScript_File_Device` subclass that
 * pipes PostScript to `lp`/`lpr` -- vs. `Fl_WinAPI_Printer_Driver` on
 * Windows -- a native `PrintDlg()`/GDI driver with no PostScript
 * involved at all), so this project splits it the same way it already
 * splits the windowing layer (`fl.platform_x11`/`fl.platform_win32`):
 * one real implementation module per platform (`fl.printer_posix`/
 * `fl.printer_win32`), each providing its own concrete `Printer` class,
 * selected here by `version()` so every caller can just `import
 * fl.printer;` and use `Printer` regardless of platform. See
 * `fl.printer_posix`'s own doc comment for why this dispatcher exists
 * now when it didn't before (this module used to *be* the POSIX
 * implementation directly).
 */
module fl.printer;

version (Windows)
    public import fl.printer_win32;
else
    public import fl.printer_posix;
