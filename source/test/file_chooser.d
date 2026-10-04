// D transliteration of FLTK's test/file_chooser.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh file_chooser
import fl;
import std.format : format;
import std.process : environment, executeShell;
import std.stdio : File, KeepTerminator;

enum TERMINAL_HEIGHT = 120;
enum TERMINAL_GREEN = "\033[32m";
enum TERMINAL_NORMAL = "\033[0m";

// FLTK's Fl_Menu_::add(const char*) '|'-separated multi-item form is
// the Forms-compatible shim CLAUDE.md marks out of scope; split locally
// and add each item via the real 4-arg add() instead.
void addPipeItems(Menu_ m, string items)
{
    import std.string : split;

    foreach (item; items.split('|'))
        m.add(item, 0, null);
}

//
// Globals...
//

Input filter;
FileBrowser files;
FileChooser fc;
SharedImage image;
Terminal tty;

// for choosing extra groups
Choice chExtra;
// first extra group
FlGroup encodings;
Choice chEnc;
// second extra widget (FLTK's local is named "version", a D keyword,
// so renamed versionBtn)
CheckButton versionBtn;

//
// Functions...
//

void closeCallback();
void createCallback();
void dirCallback();
void fcCallback(FileChooser, Object);
void multiCallback();
Image pdfCheck(string, ubyte[], int);
Image psCheck(string, ubyte[], int);
void showCallback();

void extraCallback(Widget);

void main()
{
    // Make the file chooser...
    scheme(null);
    loadSystemIcons();

    fc = new FileChooser(".", "*", single, "FileChooser Test");
    fc.callback((chooser) { fcCallback(chooser, null); });

    // Register the PS and PDF image types...
    // SharedHandler is Image delegate(string, const(ubyte)[]) -- no
    // separate length param, unlike FLTK's C callback (the slice
    // already carries its own length); pdfCheck()/psCheck()'s trailing
    // int param is unused by either body, so it's just discarded here.
    SharedImage.addHandler((name, header) => pdfCheck(name, header.dup, 0));
    SharedImage.addHandler((name, header) => psCheck(name, header.dup, 0));

    // Make the main window...
    auto window = new DoubleWindow(400, 215 + TERMINAL_HEIGHT, "File Chooser Test");

    tty = new Terminal(0, 215, window.w(), TERMINAL_HEIGHT);
    tty.ansi(true);
    tty.displayColumns(100); // at least 100 cols wide, even tho actual window smaller

    // FlGroup: limit resizing to filter input (not browse button)
    auto grp = new FlGroup(0, 10, 400, 25);
    grp.begin();
    {
        filter = new Input(50, 10, 315, 25, "Filter:");
        // FLTK scans argc/argv here for an optional filter argument;
        // dropped along with argc/argv (see samples/README.md and
        // test/button.cxx's precedent), keeping just the default filter.
        filter.value("PDF Files (*.pdf)\t"
            ~ "PostScript Files (*.ps)\t"
            ~ "Image Files (*.{bmp,gif,jpg,png})\t"
            ~ "D Source Files (*.d)");

        auto button = new Button(365, 10, 25, 25);
        button.tooltip("Click to open file browser..");
        button.callback((w) { showCallback(); });
        auto icon = FileIcon.find(".", FileType.directory);
        if (icon !is null)
        {
            // Icon found; assign it..
            button.labelcolor(yellow);
            icon.label(button);
        }
        else
        {
            // Fallback if no icon found
            button.label("..");
        }
    }
    grp.end();
    grp.resizable(filter);

    // FlGroup: prevent resizing of the light buttons
    grp = new FlGroup(0, 45, 400, 55);
    grp.begin();
    {
        auto button = new LightButton(50, 45, 80, 25, "MULTI");
        button.callback((w) { multiCallback(); });

        button = new LightButton(140, 45, 90, 25, "CREATE");
        button.callback((w) { createCallback(); });

        button = new LightButton(240, 45, 115, 25, "DIRECTORY");
        button.callback((w) { dirCallback(); });

        chExtra = new Choice(150, 75, 150, 25, "Extra Group:");
        addPipeItems(chExtra, "none|encodings group|check button");
        chExtra.value(0);
        chExtra.callback((w) { extraCallback(w); });
    }
    grp.end();
    grp.resizable(null);

    files = new FileBrowser(50, 105, 340, 75, "Files:");
    files.alignment(alignLeft);

    // Prevent resizing close button, but keep at right edge of scrn
    grp = new FlGroup(0, 185, 400, 25);
    grp.begin();
    {
        auto invis = new Box(100, 185, 1, 1);
        invis.box(Boxtype.noBox);
        auto button = new Button(310, 185, 80, 25, "Close");
        button.callback((w) { closeCallback(); });
        grp.resizable(invis);
    }
    grp.end();

    window.resizable(files);
    window.end();
    window.show();

    fl.run();
}

void extraCallback(Widget w)
{
    auto choice = cast(Choice) w;
    int val = choice.value();
    if (val == 0)
        fc.addExtra(null);
    else if (val == 1)
    {
        if (encodings is null)
        {
            encodings = new FlGroup(0, 0, 254, 30);
            chEnc = new Choice(152, 2, 100, 25, "Choose Encoding:");
            addPipeItems(chEnc, "ASCII|Koi8-r|win1251|Utf-8");
            encodings.end();
        }
        fc.addExtra(encodings);
    }
    else
    {
        if (versionBtn is null)
            versionBtn = new CheckButton(5, 0, 200, 25, "Save binary 1.0 version");
        fc.addExtra(versionBtn);
    }
}

void closeCallback()
{
    fl.hideAllWindows();
}

void createCallback()
{
    fc.type(fc.type() ^ create);
}

void dirCallback()
{
    fc.type(fc.type() ^ directoryType);
}

void fcCallback(FileChooser chooser, Object data)
{
    tty.printf("fc_callback(fc = %s, data = %s)\n", chooser, data);

    string filename = chooser.value();

    tty.printf("    filename = \"%s\"\n", filename !is null ? filename : "(null)");
}

void multiCallback()
{
    fc.type(fc.type() ^ multi);
}

Image pdfCheck(string name, ubyte[] header, int)
{
    if (header.length < 4 || header[0 .. 4] != "%PDF") return null;

    string home = environment.get("HOME", null);
    string preview = format("%s/.preview.ppm", home !is null ? home : "");

    string command = format(
        "gs -r100 -dFIXED -sDEVICE=ppmraw -dQUIET -dNOPAUSE -dBATCH "
        ~ "-sstdout=\"%%stderr\" -sOUTPUTFILE='%s' "
        ~ "-dFirstPage=1 -dLastPage=1 '%s' 2>/dev/null", preview, name);

    if (executeShell(command).status != 0) return null;

    return new PNMImage(preview);
}

Image psCheck(string name, ubyte[] header, int)
{
    if (header.length < 2 || header[0 .. 2] != "%!") return null;

    string home = environment.get("HOME", null);
    string preview = format("%s/.preview.ppm", home !is null ? home : "");
    string outname;

    if (header.length >= 4 && header[0 .. 4] == "%!PS")
    {
        // PS file has DSC comments; extract the first page...
        outname = format("%s/.preview.ps", home !is null ? home : "");

        if (name != outname)
        {
            auto inFile = File(name, "rb");
            auto outFile = File(outname, "wb");
            int page = 0;

            foreach (line; inFile.byLine(KeepTerminator.yes))
            {
                if (line.length >= 7 && line[0 .. 7] == "%%Page:")
                {
                    page++;
                    if (page > 1) break;
                }
                outFile.write(line);
            }

            inFile.close();
            outFile.close();
        }
    }
    else
    {
        // PS file doesn't have DSC comments; do the whole file...
        outname = name;
    }

    string command = format(
        "gs -r100 -dFIXED -sDEVICE=ppmraw -dQUIET -dNOPAUSE -dBATCH "
        ~ "-sstdout=\"%%stderr\" -sOUTPUTFILE='%s' '%s' 2>/dev/null",
        preview, outname);

    if (executeShell(command).status != 0) return null;

    return new PNMImage(preview);
}

void showCallback()
{
    if (filter.value().length && filter.value()[0])
        fc.filter(filter.value());

    fc.show();

    while (fc.visible())
        fl.wait();

    int count = fc.count();
    if (count > 0)
    {
        files.clear();

        for (int i = 1; i <= count; i++)
        {
            if (fc.value(i) is null) break;
            string relative = filenameRelative(fc.value(i));
            tty.printf("%d/%d) %sPicked: '%s'\n     Relative: '%s'%s\n", i, count,
                TERMINAL_GREEN, fc.value(i), relative, TERMINAL_NORMAL);
            files.add(relative, FileIcon.find(fc.value(i), FileType.plain));
        }

        files.redraw();
    }
}
