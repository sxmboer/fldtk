/*
 * Ported from FL/Fl_Printer.H + src/Fl_Printer.cxx +
 * src/drivers/Posix/Fl_Posix_Printer_Driver.cxx + src/print_panel.{h,
 * cxx} (FLTK 1.5.0).
 *
 * The Linux/X11/Wayland half of `fl.printer`'s platform split -- see
 * that module's own (tiny) doc comment for why a `version()`-selected
 * dispatcher module now exists at all. **Correction (2026-09-15): this
 * used to be `fl.printer` itself**, on the reasoning that FLTK's own
 * `Fl_Posix_Printer_Driver` had no second implementation in this port to
 * justify a real split (the "no polymorphic driver hierarchy with only
 * one implementation" precedent also used for `fl.widget_surface.
 * CopySurface`/`fl.image_surface.ImageSurface`). That premise stopped
 * holding the moment Windows printing needed a real implementation:
 * FLTK's own `Fl_WinAPI_Printer_Driver` (`fl.printer_win32`, see
 * that module) shares essentially nothing with this file -- different
 * base class (`Fl_Paged_Device` directly, not `Fl_PostScript_File_
 * Device`), no `print_panel`-style dialog at all (`PrintDlg()` -- a
 * native OS common dialog -- already lists installed printers, so
 * there's no FLTK-drawn dialog to port), and a completely different
 * page-emission mechanism (native GDI drawing into the printer's own
 * `HDC`, not PostScript piped to a subprocess). Two real, independent
 * implementations is exactly this project's own stated trigger for a
 * real split (see `fl.platform_x11`/`fl.platform_win32`'s identical
 * shape for the windowing layer) -- moved here unchanged apart from this
 * comment and the module/version declarations just below.
 *
 * `Fl_Printer` FLTK is a thin wrapper delegating to a platform-
 * specific driver (`Fl_Posix_Printer_Driver`, itself a
 * `Fl_PostScript_File_Device` subclass, or the optional `dlopen()`'d
 * `Fl_GTK_Printer_Driver` when GTK happens to be installed). This module
 * folds `Fl_Printer` + `Fl_Posix_Printer_Driver` into one concrete
 * class, `Printer`, matching this port's usual treatment when a single
 * platform's own driver is the only implementation *for that platform*
 * (Windows' own `Printer`, in `fl.printer_win32`, does the identical
 * fold on its own, unrelated internals).
 *
 * Deliberately NOT ported: `Fl_GTK_Printer_Driver`. It `dlopen()`s GTK
 * at runtime purely for a native-looking print dialog -- FLTK's own
 * doc comment: "real printing works without it" -- a cosmetic
 * enhancement layered on top of the always-available FLTK dialog this
 * module *does* port, not a functional requirement. Reimplementing a
 * runtime GTK binding is a large, separate undertaking with no
 * printing-correctness payoff; raise it separately if ever wanted.
 *
 * `PrintPanel` (the D name for FLTK's file-static `print_panel`/
 * `print_properties_panel` pair and their supporting globals/
 * callbacks in `print_panel.cxx`) is a near-pixel-faithful port,
 * geometry included, matching FLTK's own layout numbers
 * (`465x235`) exactly. The rule this module follows throughout:
 * **restore anything a user can actually see**
 * (even if disabled/inert), **only drop what FLTK itself
 * creates and then permanently `hide()`s**, since that has zero
 * possible visual difference from not creating it at all. Concretely:
 *  - **No `void* user_data()` smuggling a raw printer name through
 *    each `Fl_Choice` entry** (FLTK's `Fl_Menu_Item::user_data()`
 *    has no D equivalent at all -- see `fl.menu_item`'s own doc
 *    comment). Replaced with a plain parallel `string[] printerNames_`
 *    array, index-aligned with `printChoice_`'s items (index 0 is
 *    always the "Print To File" placeholder, matching FLTK's
 *    `user_data() == NULL` convention for that same entry).
 *  - **The "Selection" radio button is ported** (`printSelection_`)
 *    -- FLTK's own `begin_job()` unconditionally calls
 *    `print_selection->deactivate()` every time the panel is shown, so
 *    it's genuinely inert (can never be clicked), but it's still
 *    visible, at its real position, same as real FLTK.
 *    `PrintPanel.prepareForJob()` calls
 *    `printSelection_.deactivate()` every time, matching FLTK's own
 *    `begin_job()`.
 *  - **Both "stacked pages" collate-preview `Fl_Group`s (9 `Fl_Box`es
 *    each, `print_collate_group[0]`/`[1]`) are ported now, and
 *    `printCollate_`'s own toggle callback (`cb_print_collate_button`)
 *    is wired up for real** -- see the next bullet for why this one
 *    differs from a strict port: FLTK's own Collate checkbox is
 *    permanently `deactivate()`d with no reachable reactivation path
 *    (`cb_print_copies()`'s own reactivating `else` branch is
 *    commented-out dead C++ even in real FLTK), which would make both
 *    groups exactly as unreachable as the `Fl_Progress` bar below --
 *    but this port deliberately gives Collate a real, reachable
 *    "on" state (see `updateCollateState()`), so both preview groups
 *    are genuinely live UI here, not decoration.
 *  - **Collate activates when it's actually meaningful, not never**
 *    (`PrintPanel.updateCollateState()`, called from `printCopies_`'s
 *    callback and from `prepareForJob()`) -- **deliberate deviation
 *    from FLTK, at the user's explicit request** after reviewing
 *    the faithfully-ported original (permanently-disabled) behavior.
 *    Collate only means anything when a job has more than one page
 *    *and* more than one copy is requested; FLTK's own intent
 *    (visible in the dead code) was clearly to activate/deactivate on
 *    copy count, it just never got finished. This port completes that
 *    intent with the added page-count condition, rather than either
 *    leaving the control permanently dead (matches real FLTK exactly,
 *    but is arguably a UX bug) or reactivating it on copy count alone
 *    (would allow "collate" on a 1-page job, which is meaningless).
 *  - **The Properties sub-panel's 4-button color/gray x portrait/
 *    landscape output-mode picker is ported now too** (`printOutputMode_`,
 *    a `Button[4]` with `type(radioButton)` for mutual exclusion within
 *    their shared `Fl_Group`, matching FLTK's own plain-`Fl_Button`-
 *    with-radio-type design rather than `fl.round_button`). The actual
 *    color-vs-gray XPM icons (`image_print_color`/`image_print_gray`,
 *    ported verbatim as `printColorXpm`/`printGrayXpm`, decoded once
 *    into `colorPixmap_`/`grayPixmap_`) are real now too. Note this is
 *    still cosmetic-only for output correctness:
 *    `PostscriptGraphicsDriver` has no grayscale-vs-color rendering
 *    mode, and neither does FLTK's own
 *    `Fl_Posix_Printer_Driver::begin_job()` -- `print_output_mode[0]`/
 *    `[2]` both map to `PORTRAIT`, `[1]`/`[3]` both map to `LANDSCAPE`;
 *    only the portrait/landscape half of the 2x2 grid ever reaches real
 *    PostScript output, same as before this correction. What changed is
 *    the *dialog's own appearance* now matches FLTK exactly (four
 *    bordered swatch buttons instead of two plain radio buttons), which
 *    is what an earlier pass's "not worth ~80 lines of boilerplate"
 *    reasoning under-weighted -- the preferences key reverts to
 *    FLTK's own `output_mode` (storing 0-3, not a 0/1 orientation
 *    flag) to match.
 *  - **The `Fl_Progress` bar is (still) dropped.** FLTK creates it,
 *    hides it, and never shows or drives it anywhere in `begin_job()`
 *    -- dead even in real FLTK, and unlike the widgets above,
 *    genuinely never visible in any reachable state (perhaps intended
 *    for a future multi-page progress indicator that was never wired
 *    up).
 *  - **`popen()`/`pclose()` become `std.process.pipeShell()`/
 *    `std.process.wait()`.** `pipeShell(cmd, Redirect.stdin)` spawns
 *    via `/bin/sh -c` exactly like `popen(cmd, "w")` does, returning a
 *    `std.stdio.File` for the child's stdin (assigned to
 *    `PostscriptFileDevice`'s own `File`-based `beginJob()` overload,
 *    see that class's row in `PORTING.md`); `Printer.endJob()` closes
 *    that `File` explicitly (signaling EOF to `lp`/`lpr` the same way
 *    `fclose()` on a `popen()` pipe would) before `wait()`ing on the
 *    child, since `PostscriptFileDevice.beginJob(File, ...)` itself
 *    deliberately leaves caller-supplied `File`s open (`closesFile_ =
 *    false` -- the caller, here, still owns closing it).
 *
 * `printLoad()`/`printUpdateStatus()`'s actual `lpstat -p -d`/
 * `/etc/printcap` parsing is factored into pure, unit-testable
 * functions (`parseLpstatOutput()`/`parsePrintcap()`) separate from the
 * subprocess-spawning glue, matching this port's usual "parsing
 * separate from I/O" precedent (e.g. `fl.draw`'s `dashPatternFor()`) --
 * `beginJob()`'s own interactive dialog can't be exercised headlessly
 * (needs a live X server and a user click, same reasoning
 * `fl.native_file_chooser`/`fl.ask` don't drive `show()` in `dub
 * test`), so those two parsers are what this module's `unittest`
 * blocks actually cover.
 */
module fl.printer_posix;

// No `version (linux):` guard: `fl.printer`'s own dispatcher only ever
// selects this module's `Printer` by default on non-Windows platforms
// (see that module), but the class itself compiles everywhere --
// nothing in it is actually Linux-specific (`std.process.pipeShell()`/
// `executeShell()`, `std.file.exists()`, and every `fl.*` widget import
// below are all cross-platform Phobos/fldtk). Kept buildable on Windows
// too so `smoke-tests/printer_fltk_dialog.d` can construct this
// `Printer` directly there, purely to visually preview the FLTK-drawn
// `PrintPanel` dialog -- see that smoke test's own header comment for
// why (short version: it can't actually enumerate printers or submit a
// job on Windows, since `lpstat`/`lp`/`lpr` don't exist there; it's a
// UI-only smoke test, not a working printing path on that platform).

import fl.paged_device : PageFormat, PageLayout,
    letter, a4, legal, executive, a3, a5, b5, dle, tabloid, envelope,
    portrait, landscape;
import fl.postscript : PostscriptFileDevice;
import fl.double_window : DoubleWindow;
import fl.group : FlGroup;
import fl.choice : Choice;
import fl.button : Button, radioButton;
import fl.radio_round_button : RadioRoundButton;
import fl.box : Box;
import fl.int_input : IntInput;
import fl.spinner : Spinner;
import fl.check_button : CheckButton;
import fl.return_button : ReturnButton;
import fl.widget : Widget;
import fl.pixmap : Pixmap;
import fl.menu_item : MenuItem, menuDivider;
import fl.preferences : Preferences, rootCoreUser;
import fl.enumerations : Boxtype, alignTopLeft, alignLeft, alignInside,
    alignClip, alignBottomRight, bold, whenChanged, courier,
    foregroundColor, background2Color;
static import fl.core;

import std.process : executeShell, pipeShell, Redirect, wait, Pid;
import std.string : strip, splitLines, startsWith;
import std.string : indexOf;
import std.conv : to;
import std.file : exists, readText;
import std.format : format;
import std.array : appender;
import std.stdio : File;

/// Ported from `printing_style` (`print_panel.h`) -- which of the two
/// Unix print-spooler command families (`lp` vs `lpr`) is in use.
enum PrintingStyle
{
    systemV,
    bsd,
}

/// Escapes `/` as `\/` for display in a flat `Fl_Choice` label (the
/// menu system otherwise reads `/` as a submenu path separator).
/// Ported from `print_load()`'s `qname`-building loop. The *raw* name
/// (unescaped) is what actually gets used in shell commands --
/// see `PrintPanel.printerNames_`.
private string escapeMenuLabel(string name)
{
    auto result = appender!string;
    foreach (c; name)
    {
        if (c == '/') result.put('\\');
        result.put(c);
    }
    return result.data;
}

/// Parses `lpstat -p -d`'s stdout into the raw printer names it lists
/// (in encounter order) plus the reported system default printer name
/// (`""` if none reported). Ported from `print_load()`'s SystemV
/// parsing loop.
void parseLpstatOutput(string output, out string[] names, out string defaultName)
{
    enum printerPrefix = "printer ";
    enum defaultPrefix = "system default destination: ";
    foreach (line; output.splitLines())
    {
        if (line.startsWith(printerPrefix))
        {
            auto rest = line[printerPrefix.length .. $];
            auto sp = rest.indexOf(' ');
            string name = strip(sp >= 0 ? rest[0 .. sp] : rest);
            if (name.length) names ~= name;
        }
        else if (line.startsWith(defaultPrefix))
        {
            defaultName = strip(line[defaultPrefix.length .. $]);
        }
    }
}

/// Parses `/etc/printcap`'s BSD-style printer database into a list of
/// raw printer names. Ported from `print_load()`'s BSD-fallback
/// parsing loop. Simplification: FLTK's own loop tracks `\`-
/// continued capability lines by re-reading with `fgets()`; this port
/// reads the whole file up front (`std.file.readText()`), so
/// continuation lines are simply skipped (their content -- printcap
/// capability strings -- was never used beyond the name anyway).
string[] parsePrintcap(string content)
{
    string[] names;
    bool continued = false;
    foreach (line; content.splitLines())
    {
        if (continued)
        {
            continued = line.length > 0 && line[$ - 1] == '\\';
            continue;
        }
        if (line.length == 0 || line[0] == '#') continue;
        auto bar = line.indexOf('|');
        if (bar < 0)
        {
            continued = line.length > 0 && line[$ - 1] == '\\';
            continue;
        }
        names ~= line[0 .. bar];
        continued = line.length > 0 && line[$ - 1] == '\\';
    }
    return names;
}

private int parseIntOr(string s, int def)
{
    try
        return to!int(strip(s));
    catch (Exception)
        return def;
}

/// Ported from `menu_print_page_size[]` (`print_panel.cxx`).
private MenuItem[] pageSizeMenuItems()
{
    return [
        MenuItem("Letter"), MenuItem("A4"), MenuItem("Legal"),
        MenuItem("Executive"), MenuItem("A3"), MenuItem("A5"),
        MenuItem("B5"), MenuItem("Com10"), MenuItem("DL"),
        MenuItem("Tabloid"), MenuItem(null),
    ];
}

/// Index-aligned with `pageSizeMenuItems()` -- ported from
/// `Fl_Posix_Printer_Driver::begin_job()`'s `switch (print_page_size->
/// value())`.
private static immutable PageFormat[10] pageSizeFormats = [
    letter, a4, legal, executive, a3, a5, b5, envelope, dle, tabloid,
];

/// Ported verbatim from `idata_print_color[]` (`print_panel.cxx`) --
/// the "color" swatch icon shared by `printOutputMode_[0]`/`[1]`.
private static immutable string[] printColorXpm = [
    "24 24 17 1",
    " \tc None",
    ".\tc #FFFF00",
    "+\tc #C8FF00",
    "@\tc #00FF00",
    "#\tc #FFC800",
    "$\tc #FF0000",
    "%\tc #00FFFF",
    "&\tc #000000",
    "*\tc #FF00FF",
    "=\tc #00FFC8",
    "-\tc #FF00C8",
    ";\tc #00C800",
    ">\tc #C80000",
    ",\tc #0000C8",
    "'\tc #0000FF",
    ")\tc #00C8FF",
    "!\tc #C800FF",
    "         ......         ",
    "       ..........       ",
    "      ............      ",
    "     ..............     ",
    "     ..............     ",
    "    ................    ",
    "    ................    ",
    "    ................    ",
    "    +@@@@@@+#$$$$$$#    ",
    "   %@@@@@@@&&$$$$$$$*   ",
    "  %%@@@@@@&&&&$$$$$$**  ",
    " %%%=@@@@&&&&&&$$$$-*** ",
    " %%%%@@@;&&&&&&>$$$**** ",
    "%%%%%%@@&&&&&&&&$$******",
    "%%%%%%%@&&&&&&&&$*******",
    "%%%%%%%%,&&&&&&,********",
    "%%%%%%%%''''''''********",
    "%%%%%%%%''''''''********",
    "%%%%%%%%''''''''********",
    " %%%%%%%)''''''!******* ",
    " %%%%%%%%''''''******** ",
    "  %%%%%%%%''''********  ",
    "   %%%%%%%%''********   ",
    "     %%%%%%  ******     ",
];

/// Ported verbatim from `idata_print_gray[]` (`print_panel.cxx`) --
/// the "gray" swatch icon shared by `printOutputMode_[2]`/`[3]`.
private static immutable string[] printGrayXpm = [
    "24 24 17 1",
    " \tc None",
    ".\tc #E3E3E3",
    "+\tc #D2D2D2",
    "@\tc #969696",
    "#\tc #C2C2C2",
    "$\tc #4C4C4C",
    "%\tc #B2B2B2",
    "&\tc #000000",
    "*\tc #696969",
    "=\tc #ACACAC",
    "-\tc #626262",
    ";\tc #767676",
    ">\tc #3C3C3C",
    ",\tc #161616",
    "'\tc #1C1C1C",
    ")\tc #929292",
    "!\tc #585858",
    "         ......         ",
    "       ..........       ",
    "      ............      ",
    "     ..............     ",
    "     ..............     ",
    "    ................    ",
    "    ................    ",
    "    ................    ",
    "    +@@@@@@+#$$$$$$#    ",
    "   %@@@@@@@&&$$$$$$$*   ",
    "  %%@@@@@@&&&&$$$$$$**  ",
    " %%%=@@@@&&&&&&$$$$-*** ",
    " %%%%@@@;&&&&&&>$$$**** ",
    "%%%%%%@@&&&&&&&&$$******",
    "%%%%%%%@&&&&&&&&$*******",
    "%%%%%%%%,&&&&&&,********",
    "%%%%%%%%''''''''********",
    "%%%%%%%%''''''''********",
    "%%%%%%%%''''''''********",
    " %%%%%%%)''''''!******* ",
    " %%%%%%%%''''''******** ",
    "  %%%%%%%%''''********  ",
    "   %%%%%%%%''********   ",
    "     %%%%%%  ******     ",
];

/**
 * The D name for FLTK's file-static `print_panel`/
 * `print_properties_panel` pair (`print_panel.cxx`) -- built once,
 * lazily, and reused for every `Printer.beginJob()` call thereafter
 * (matching FLTK's own `if (!print_panel) make_print_panel();`),
 * but as a real object instead of a scattering of module-level
 * globals -- FLTK's own top-of-file comment calls the global-
 * variable design a known wart ("The use of static variables should be
 * avoided").
 */
private class PrintPanel
{
    DoubleWindow window_;
    Choice printChoice_;
    Button printProperties_;
    Box printStatus_;
    RadioRoundButton printAll_;
    RadioRoundButton printPages_;
    RadioRoundButton printSelection_;
    IntInput printFrom_;
    IntInput printTo_;
    Spinner printCopies_;
    CheckButton printCollate_;
    FlGroup[2] printCollateGroup_;

    DoubleWindow propertiesWindow_;
    Choice printPageSize_;
    Button[4] printOutputMode_;

    bool printStarted_;
    string[] printerNames_ = [""]; // index 0: "Print To File" placeholder

    /// The job's page count, as last passed to `prepareForJob()` --
    /// needed by `updateCollateState()`, a deliberate deviation from
    /// FLTK (see that method's own doc comment).
    private int pageCount_ = 1;

    /// Lazily-shared, matching FLTK's own file-static
    /// `image_print_color`/`image_print_gray` -- built once, reused by
    /// every `printOutputMode_[]` button that needs that color.
    private static Pixmap colorPixmap_;
    private static Pixmap grayPixmap_;

    /// Ported from `print_collate_group[0]`/`[1]`'s 9 `Fl_Box`es each
    /// (`print_panel.cxx`) -- the "1,1,1 / 2,2,2 / 3,3,3" (unchecked)
    /// vs. "1,2,3 / 1,2,3 / 1,2,3" (checked) stacked-page preview,
    /// toggled by `printCollate_`'s callback. `deactivateBox` matches
    /// FLTK exactly: group `[0]`'s own boxes each call
    /// `deactivate()` individually (on top of the group itself being
    /// deactivated), group `[1]`'s don't -- a Fluid-generated asymmetry
    /// with no visible effect on a plain `Fl_Box` either way, kept only
    /// for faithfulness.
    private static void addCollateStackBox(int x, int y, string label,
        bool deactivateBox = true)
    {
        auto o = new Box(x, y, 30, 40, label);
        o.box(Boxtype.borderBox);
        o.color(background2Color);
        o.labelsize(11);
        o.alignment(alignBottomRight | alignInside);
        if (deactivateBox) o.deactivate();
    }

    this()
    {
        auto previousGroup = FlGroup.current();
        FlGroup.current(null);

        window_ = new DoubleWindow(465, 235, Printer.dialogTitle);
        auto controls = new FlGroup(10, 10, 447, 216);
        {
            printChoice_ = new Choice(133, 10, 181, 25, Printer.dialogPrinter);
            printChoice_.labelfont(bold);
            printChoice_.callback((w) { updateStatus(); });
            printChoice_.when(whenChanged);

            printProperties_ = new Button(314, 10, 115, 25, Printer.dialogProperties);
            printProperties_.callback((w) { propertiesWindow_.show(); });

            printStatus_ = new Box(0, 41, controls.w(), 17, "");
            printStatus_.alignment(alignClip | alignInside | alignLeft);

            auto rangeGroup = new FlGroup(10, 86, 227, 105, Printer.dialogRange);
            rangeGroup.box(Boxtype.thinDownBox);
            rangeGroup.labelfont(bold);
            rangeGroup.alignment(alignTopLeft);
            {
                printAll_ = new RadioRoundButton(20, 96, 38, 25, Printer.dialogAll);
                printAll_.value(true);
                printAll_.callback((w) {
                    printFrom_.deactivate();
                    printTo_.deactivate();
                });

                printPages_ = new RadioRoundButton(20, 126, 64, 25, Printer.dialogPages);
                printPages_.callback((w) {
                    printFrom_.activate();
                    printTo_.activate();
                });

                printSelection_ = new RadioRoundButton(20, 156, 82, 25, "Selection");
                printSelection_.callback((w) {
                    printFrom_.deactivate();
                    printTo_.deactivate();
                });

                printFrom_ = new IntInput(136, 126, 28, 25, Printer.dialogFrom);
                printFrom_.textfont(courier);
                printFrom_.deactivate();

                printTo_ = new IntInput(199, 126, 28, 25, Printer.dialogTo);
                printTo_.textfont(courier);
                printTo_.deactivate();
            }
            rangeGroup.end();

            auto copiesGroup = new FlGroup(247, 86, 210, 105, Printer.dialogCopies);
            copiesGroup.box(Boxtype.thinDownBox);
            copiesGroup.labelfont(bold);
            copiesGroup.alignment(alignTopLeft);
            {
                printCopies_ = new Spinner(321, 96, 45, 25, Printer.dialogCopyNo);
                printCopies_.minimum(1);
                printCopies_.value(1);
                printCopies_.when(whenChanged);
                printCopies_.callback((w) { updateCollateState(); });

                printCollate_ = new CheckButton(376, 96, 64, 25, "Collate");
                printCollate_.when(whenChanged);
                printCollate_.deactivate();
                printCollate_.callback((w) {
                    int i = printCollate_.value() ? 1 : 0;
                    printCollateGroup_[i].show();
                    printCollateGroup_[1 - i].hide();
                });

                printCollateGroup_[0] = new FlGroup(257, 131, 191, 50);
                printCollateGroup_[0].deactivate();
                {
                    addCollateStackBox(287, 141, "1");
                    addCollateStackBox(272, 136, "1");
                    addCollateStackBox(257, 131, "1");
                    addCollateStackBox(352, 141, "2");
                    addCollateStackBox(337, 136, "2");
                    addCollateStackBox(322, 131, "2");
                    addCollateStackBox(417, 141, "3");
                    addCollateStackBox(402, 136, "3");
                    addCollateStackBox(387, 131, "3");
                }
                printCollateGroup_[0].end();

                printCollateGroup_[1] = new FlGroup(257, 131, 191, 50);
                printCollateGroup_[1].hide();
                printCollateGroup_[1].deactivate();
                {
                    addCollateStackBox(287, 141, "3", false);
                    addCollateStackBox(272, 136, "2", false);
                    addCollateStackBox(257, 131, "1", false);
                    addCollateStackBox(352, 141, "3", false);
                    addCollateStackBox(337, 136, "2", false);
                    addCollateStackBox(322, 131, "1", false);
                    addCollateStackBox(417, 141, "3", false);
                    addCollateStackBox(402, 136, "2", false);
                    addCollateStackBox(387, 131, "1", false);
                }
                printCollateGroup_[1].end();
            }
            copiesGroup.end();

            auto print = new ReturnButton(279, 201, 100, 25, Printer.dialogPrintButton);
            print.callback((w) { printStarted_ = true; window_.hide(); });

            auto cancel = new Button(389, 201, 68, 25, Printer.dialogCancelButton);
            cancel.callback((w) { printStarted_ = false; window_.hide(); });
        }
        controls.end();
        window_.setModal();
        window_.end();

        propertiesWindow_ = new DoubleWindow(290, 130, Printer.propertyTitle);
        {
            printPageSize_ = new Choice(150, 10, 80, 25, Printer.propertyPagesize);
            printPageSize_.menu(pageSizeMenuItems());

            auto modeGroup = new FlGroup(110, 45, 170, 40, Printer.propertyMode);
            modeGroup.alignment(alignLeft);
            {
                if (colorPixmap_ is null) colorPixmap_ = new Pixmap(printColorXpm.dup);
                if (grayPixmap_ is null) grayPixmap_ = new Pixmap(printGrayXpm.dup);

                printOutputMode_[0] = new Button(110, 45, 30, 40);
                printOutputMode_[1] = new Button(150, 50, 40, 30);
                printOutputMode_[2] = new Button(200, 45, 30, 40);
                printOutputMode_[3] = new Button(240, 50, 40, 30);
                foreach (i, btn; printOutputMode_)
                {
                    btn.type(radioButton);
                    btn.box(Boxtype.borderBox);
                    btn.downBox(Boxtype.borderBox);
                    btn.color(background2Color);
                    btn.selectionColor(foregroundColor);
                    btn.image(i < 2 ? colorPixmap_ : grayPixmap_);
                }
                printOutputMode_[0].value(true);
            }
            modeGroup.end();

            auto save = new ReturnButton(93, 95, 99, 25, Printer.propertySave);
            save.callback((w) { save_(); propertiesWindow_.hide(); });

            auto propCancel = new Button(202, 95, 78, 25, Printer.propertyCancel);
            propCancel.callback((w) { propertiesWindow_.hide(); updateStatus(); });

            auto use = new Button(10, 95, 73, 25, Printer.propertyUse);
            use.callback((w) { propertiesWindow_.hide(); });
        }
        propertiesWindow_.callback((w) { propertiesWindow_.hide(); updateStatus(); });
        propertiesWindow_.setModal();
        propertiesWindow_.end();

        FlGroup.current(previousGroup);
    }

    /// Ported from `print_load()`.
    PrintingStyle load()
    {
        printerNames_ = [""];
        printChoice_.clear();
        printChoice_.add(Printer.dialogPrintToFile, 0, null, menuDivider);
        printChoice_.value(0);
        printStarted_ = false;

        auto style = PrintingStyle.systemV;
        string defaultName;

        auto result = executeShell(
            "LC_MESSAGES=C LANG=C /bin/sh -c '(lpstat -p -d ) 2>&-'");
        string[] names;
        parseLpstatOutput(result.output, names, defaultName);
        foreach (name; names)
        {
            printChoice_.add(escapeMenuLabel(name), 0, null, 0);
            printerNames_ ~= name;
        }

        if (printerNames_.length <= 1 && exists("/etc/printcap"))
        {
            string[] pcNames;
            try
                pcNames = parsePrintcap(readText("/etc/printcap"));
            catch (Exception)
            {
            }
            foreach (name; pcNames)
            {
                style = PrintingStyle.bsd;
                printChoice_.add(escapeMenuLabel(name), 0, null, 0);
                printerNames_ ~= name;
            }
            import std.process : environment;

            defaultName = environment.get("PRINTER", "lp");
        }

        if (printerNames_.length > 1) printChoice_.value(1);
        if (defaultName.length)
        {
            foreach (i, n; printerNames_)
                if (n == defaultName)
                {
                    printChoice_.value(cast(int) i);
                    break;
                }
        }

        updateStatus();
        return style;
    }

    /// Ported from `print_update_status()`.
    void updateStatus()
    {
        int idx = printChoice_.value();
        string status;
        if (idx != 0 && idx < printerNames_.length)
        {
            string printerName = printerNames_[idx];
            status = "printer status unavailable";
            auto result = executeShell(
                format(`/bin/sh -c "(lpstat -p '%s' ) 2>&-" `, printerName));
            auto lines = result.output.splitLines();
            if (lines.length && strip(lines[0]).length)
                status = lines[0];
            else
            {
                auto result2 = executeShell(format("lpq -P%s 2>&-", printerName));
                auto lines2 = result2.output.splitLines();
                if (lines2.length) status = lines2[0];
            }
        }
        printStatus_.label(status);

        string printerName = (idx != 0 && idx < printerNames_.length)
            ? printerNames_[idx] : "";
        auto prefs = new Preferences(rootCoreUser, "fltk.org", "printers");
        int val;
        prefs.get(printerName ~ "/page_size", val, 1);
        printPageSize_.value(val);
        prefs.get(printerName ~ "/output_mode", val, 0);
        // Ported from `print_output_mode[val]->setonly();` -- FLTK
        // indexes with an unchecked value straight from
        // `Fl_Preferences` (a real out-of-bounds read on a corrupted
        // prefs file, filed as an FLTK_ISSUES.md candidate); D's
        // array bounds checking would turn that into a crash here, so
        // this port clamps instead.
        if (val < 0 || val >= printOutputMode_.length) val = 0;
        printOutputMode_[val].setonly();
    }

    /// Ported from `cb_Save()`.
    private void save_()
    {
        int idx = printChoice_.value();
        string printerName = (idx != 0 && idx < printerNames_.length)
            ? printerNames_[idx] : "";
        auto prefs = new Preferences(rootCoreUser, "fltk.org", "printers");
        prefs.set(printerName ~ "/page_size", printPageSize_.value());
        int val = 0;
        foreach (i, btn; printOutputMode_)
            if (btn.value())
            {
                val = cast(int) i;
                break;
            }
        prefs.set(printerName ~ "/output_mode", val);
    }

    /// Deliberate deviation from FLTK, at the user's request:
    /// `Fl_Posix_Printer_Driver::begin_job()`'s own dialog leaves
    /// Collate permanently `deactivate()`d -- the code that would
    /// reactivate it (`cb_print_copies()`'s `else` branch) is dead,
    /// commented-out C++ even in real FLTK (see this module's top
    /// comment and the matching `FLTK_ISSUES.md` entry). Collate
    /// only means anything when there's more than one page *and* more
    /// than one copy -- a single-page job has nothing to collate
    /// regardless of copy count, and a single copy has nothing to
    /// collate regardless of page count -- so this port activates it
    /// exactly under that combined condition instead of never.
    private void updateCollateState()
    {
        if (pageCount_ > 1 && printCopies_.value() > 1)
        {
            printCollate_.activate();
        }
        else
        {
            // Reset to the "not collated" default view -- otherwise a
            // Collate checkbox left checked from a previous, larger
            // job would show greyed-out-but-still-checked, with the
            // "collated" preview stack still showing, for a job that
            // no longer qualifies.
            printCollate_.value(false);
            printCollate_.deactivate();
            printCollateGroup_[0].show();
            printCollateGroup_[1].hide();
        }
    }

    /// Ported from the top of `Fl_Posix_Printer_Driver::begin_job()`
    /// (the part before `print_panel->show()`).
    void prepareForJob(int pages)
    {
        printSelection_.deactivate();
        printAll_.setonly();
        printAll_.doCallback();
        printFrom_.value("1");
        printTo_.value(pages.to!string);
        printStarted_ = false;
        pageCount_ = pages;
        updateCollateState();
    }

    bool printStarted() const { return printStarted_; }
    int printerIndex() const { return printChoice_.value(); }

    string printerName(int idx) const
    {
        return idx >= 0 && idx < printerNames_.length ? printerNames_[idx] : "";
    }

    bool rangeSelected() const { return printPages_.value(); }
    int fromValue() const { return parseIntOr(printFrom_.value(), 1); }
    int toValue(int def) const { return parseIntOr(printTo_.value(), def); }
    int copiesValue() const { return cast(int)(printCopies_.value() + 0.5); }
    bool collateValue() const { return printCollate_.value(); }
    string mediaName() const { return printPageSize_.text(printPageSize_.value()); }

    PageFormat selectedFormat() const
    {
        int v = printPageSize_.value();
        if (v < 0 || v >= pageSizeFormats.length) return a4;
        return pageSizeFormats[v];
    }

    /// Ported from `Fl_Posix_Printer_Driver::begin_job()`'s own
    /// `print_output_mode[0..3]` chain -- `[0]`/`[2]` (the "color"/
    /// "gray" portrait swatches) both map to `portrait`, `[1]`/`[3]`
    /// (landscape) both map to `landscape`.
    PageLayout selectedLayout() const
    {
        if (printOutputMode_[0].value()) return portrait;
        if (printOutputMode_[1].value()) return landscape;
        if (printOutputMode_[2].value()) return portrait;
        return landscape;
    }
}

private PrintPanel printPanelInstance_;

private PrintPanel printPanel()
{
    if (printPanelInstance_ is null) printPanelInstance_ = new PrintPanel();
    return printPanelInstance_;
}

/**
 * OS-independent print support. Ported from `Fl_Printer` +
 * `Fl_Posix_Printer_Driver` -- see this module's own top comment for
 * the folding-together rationale and every deliberate dialog
 * simplification.
 *
 * Usage mirrors FLTK's own documented example (`FL/Fl_Printer.H`'s
 * header comment):
 * ---
 * auto printer = new Printer();
 * int from, to;
 * string err;
 * if (printer.beginJob(1, from, to, err) == 0)
 * {
 *     printer.beginPage();
 *     int w, h;
 *     printer.printableRect(w, h);
 *     fl_color(black);
 *     fl_rect(0, 0, w, h);
 *     printer.endPage();
 *     printer.endJob();
 * }
 * ---
 */
class Printer : PostscriptFileDevice
{
    /// \name Dialog customization strings -- ported from `Fl_Printer`'s
    /// own public `static const char*` members. Plain mutable `static
    /// string`s here (not `immutable`) so callers can still override
    /// them for localization before constructing a `Printer`, matching
    /// FLTK's own documented usage.
    /// \{
    static string dialogTitle = "Print";
    static string dialogPrinter = "Printer:";
    static string dialogRange = "Print Range";
    static string dialogCopies = "Copies";
    static string dialogAll = "All";
    static string dialogPages = "Pages";
    static string dialogFrom = "From:";
    static string dialogTo = "To:";
    static string dialogProperties = "Properties...";
    static string dialogCopyNo = "# Copies:";
    static string dialogPrintButton = "Print";
    static string dialogCancelButton = "Cancel";
    static string dialogPrintToFile = "Print To File";
    static string propertyTitle = "Printer Properties";
    static string propertyPagesize = "Page Size:";
    /// Ported from `Fl_Printer::property_mode`.
    static string propertyMode = "Output Mode:";
    static string propertyUse = "Use";
    static string propertySave = "Save";
    static string propertyCancel = "Cancel";
    /// \}

    private File pipeStdin_;
    private Pid pipePid_;
    private bool pipeActive_;

    /// Convenience overload for callers that don't need the resulting
    /// page range back -- FLTK's own `begin_job(int, int*, int*,
    /// char**)` accepts `NULL` for `frompage`/`topage`, which D's `out`
    /// parameters can't express directly (there's no "don't care, skip
    /// writing to it" pointer state); this is the equivalent "I don't
    /// care" spelling.
    int beginJob(int pageCount, out string errMessage)
    {
        int fromPage, toPage;
        return beginJob(pageCount, fromPage, toPage, errMessage);
    }

    /// Ported from `Fl_PostScript_File_Device::begin_job(int, int*,
    /// int*, char**)` -- FLTK's own doc comment: "Don't use with
    /// this class" (`Printer` overrides it for real, unlike the base
    /// `PostscriptFileDevice`, which keeps the inherited "not
    /// implemented" body).
    override int beginJob(int pageCount, out int fromPage, out int toPage,
        out string errMessage)
    {
        auto panel = printPanel();
        auto style = panel.load();
        panel.prepareForJob(pageCount);

        panel.window_.show();
        while (panel.window_.shown())
            fl.core.wait();

        if (!panel.printStarted())
            return 1;

        PageFormat format_ = panel.selectedFormat();
        PageLayout layout = panel.selectedLayout();

        int from = 1, to = pageCount;
        if (panel.rangeSelected())
        {
            from = panel.fromValue();
            to = panel.toValue(pageCount);
        }
        if (from < 1) from = 1;
        if (to > pageCount) to = pageCount;
        if (to < from) to = from;
        fromPage = from;
        toPage = to;
        int pages = pageCount > 0 ? to - from + 1 : pageCount;

        int choiceIndex = panel.printerIndex();
        if (choiceIndex == 0) // "Print To File"
            return super.beginJob(pages, format_, layout);

        string printerName = panel.printerName(choiceIndex);
        int copyCount = panel.collateValue() ? 1 : panel.copiesValue();
        string media = panel.mediaName();

        string command = style == PrintingStyle.systemV
            ? .format("lp -s -d %s -n %d -t 'FLTK' -o media=%s",
                printerName, copyCount, media)
            : .format("lpr -h -P%s -#%d -T FLTK ", printerName, copyCount);

        auto pipes = pipeShell(command, Redirect.stdin);
        pipeStdin_ = pipes.stdin;
        pipePid_ = pipes.pid;
        pipeActive_ = true;

        int result = super.beginJob(pipeStdin_, pages, format_, layout);
        if (result != 0)
        {
            pipeStdin_.close();
            wait(pipePid_);
            pipeActive_ = false;
            errMessage = "could not run command: " ~ command;
            return 2;
        }
        return 0;
    }

    /// Ported from `Fl_Posix_Printer_Driver`'s implicit reliance on
    /// `Fl_PostScript_Graphics_Driver::close_command()` (here:
    /// `PostscriptFileDevice`'s own `closesFile_ = false` path for the
    /// `File`-based `beginJob()` overload -- see this module's top
    /// comment) to eventually `pclose()` the spawned `lp`/`lpr`.
    override void endJob()
    {
        super.endJob(); // writes the PostScript trailer
        if (pipeActive_)
        {
            pipeStdin_.close(); // EOF -- lets lp/lpr finish reading
            wait(pipePid_);
            pipeActive_ = false;
        }
    }
}

unittest
{
    string[] names;
    string def;
    parseLpstatOutput(
        "printer HP_LaserJet is idle.  enabled since Mon\n" ~
        "printer Epson_Photo is idle.  enabled since Mon\n" ~
        "system default destination: Epson_Photo\n",
        names, def);
    assert(names == ["HP_LaserJet", "Epson_Photo"]);
    assert(def == "Epson_Photo");
}

unittest
{
    string[] names;
    string def;
    parseLpstatOutput("no destinations added.\n", names, def);
    assert(names.length == 0);
    assert(def.length == 0);
}

unittest
{
    auto names = parsePrintcap(
        "# a comment\n" ~
        "lp|HP LaserJet:\\\n" ~
        "\t:lp=/dev/lp0:\n" ~
        "\n" ~
        "epson|Epson Photo:sd=/var/spool/epson:\n");
    assert(names == ["lp", "epson"]);
}

unittest
{
    assert(escapeMenuLabel("plain") == "plain");
    assert(escapeMenuLabel("a/b") == "a\\/b");
}

unittest
{
    assert(parseIntOr("42", 0) == 42);
    assert(parseIntOr(" 7 ", 0) == 7);
    assert(parseIntOr("nope", 9) == 9);
    assert(parseIntOr("", 9) == 9);
}
