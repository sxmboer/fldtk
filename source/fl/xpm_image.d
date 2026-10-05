/*
 * Ported from FL/Fl_XPM_Image.H + src/Fl_XPM_Image.cxx (FLTK 1.5.0): Fl_XPM_Image, an X Pixmap (XPM) file reader.
 * Milestone 3 of the fl.image port -- see fl.image's own top comment
 * for the overall staging.
 *
 * An XPM file is a valid C source fragment: a `static char *name[] =
 * {"W H ncolors chars_per_pixel", "colorspec", ..., "pixelrow", ...};`
 * array of C-string literals. Ported from `Fl_XPM_Image::
 * Fl_XPM_Image()`: reads the whole file via `std.file.readText()` and
 * splits into lines (this port's usual substitution for FLTK's
 * byte-at-a-time `fgets()` loop), taking every line starting with `"`
 * as one data row and running it through the same string-escape
 * decoder FLTK uses (`\xNN` hex, `\NNN` 1-3-digit octal, and the
 * usual C escapes) to recover the row's real content -- exactly the
 * `string[]` shape `fl.pixmap.Pixmap`'s own constructor expects, so
 * this reader just builds that array and hands it off.
 *
 * Deliberately not ported: FLTK's mid-string `\<newline>`
 * continuation escape (a row that's too long for one physical line
 * continues onto the next). No real-world XPM file needs this in
 * practice (rows are image-color-index data, comfortably within any
 * reasonable line-length limit) -- this port simply stops decoding a
 * row at its own line's end, which only differs from FLTK for
 * this one, essentially unused escape form.
 */
module fl.xpm_image;

import fl.pixmap : Pixmap, parseHeader;

class XPMImage : Pixmap
{
    this(string filename)
    {
        super(readXpmRows(filename));
    }
}

private string[] readXpmRows(string filename)
{
    import std.file : readText;
    import std.string : splitLines;

    string content;
    try
        content = readText(filename);
    catch (Exception)
        return null;

    string[] rows;
    int W, H, ncolors, cpp;

    foreach (line; content.splitLines())
    {
        if (line.length == 0 || line[0] != '"') continue;
        string row = unescapeXpmString(line);
        if (row is null) continue; // no closing quote -- malformed, skip

        if (rows.length == 0)
        {
            if (!parseHeader(row, W, H, ncolors, cpp)) return null;
        }
        rows ~= row;
    }

    int expectedRows = 1 + (ncolors < 0 ? 1 : ncolors) + H;
    if (rows.length == 0 || rows.length < expectedRows) return null;

    return rows;
}

private int hexOrOctalDigit(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'z') return c - 'a' + 10;
    if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
    return 20;
}

/**
 * Decodes one XPM quoted-string line's escapes, returning its real
 * content (without the surrounding quotes). Ported character-by-
 * character from the decode loop in `Fl_XPM_Image::Fl_XPM_Image()`
 * (which decodes in place into the same buffer it reads from; this
 * port builds a fresh output buffer instead, same "no raw pointer
 * aliasing tricks" substitution used throughout this port). Returns
 * `null` if line has no closing `"` (malformed).
 */
private string unescapeXpmString(string line)
{
    auto outBuf = new char[line.length];
    size_t outIdx = 0;
    size_t q = 1; // skip the opening quote

    while (q < line.length && line[q] != '"')
    {
        if (line[q] == '\\')
        {
            q++;
            if (q >= line.length) break;
            char esc = line[q];
            if (esc == 'x' || esc == 'X')
            {
                q++;
                int n = 0, count = 0;
                while (q < line.length && count < 2)
                {
                    int xd = hexOrOctalDigit(line[q]);
                    if (xd > 15) break;
                    n = (n << 4) + xd;
                    q++;
                    count++;
                }
                outBuf[outIdx++] = cast(char) n;
            }
            else
            {
                int c = esc;
                q++;
                if (c >= '0' && c <= '7')
                {
                    c -= '0';
                    int count = 0;
                    while (q < line.length && count < 2)
                    {
                        int xd = hexOrOctalDigit(line[q]);
                        if (xd > 7) break;
                        c = (c << 3) + xd;
                        q++;
                        count++;
                    }
                }
                outBuf[outIdx++] = cast(char) c;
            }
        }
        else
        {
            outBuf[outIdx++] = line[q];
            q++;
        }
    }
    if (q >= line.length || line[q] != '"') return null;
    return cast(string) outBuf[0 .. outIdx];
}

unittest
{
    // unescapeXpmString(): the escape forms XPM color/pixel rows
    // actually use in practice.
    assert(unescapeXpmString(`"plain text"`) == "plain text");
    assert(unescapeXpmString(`"\x41\x42"`) == "AB"); // hex
    assert(unescapeXpmString(`"\101\102"`) == "AB"); // octal
    assert(unescapeXpmString(`"no closing quote`) is null);
}

unittest
{
    // Real end-to-end file round trip via an isolated temp file.
    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import fl.pixmap : convertPixmap;
    import fl.enumerations : black;

    auto path = buildPath(tempDir(), "fldtk-xpm-test-" ~ randomUUID().toString() ~ ".xpm");
    scope (exit) if (exists(path)) remove(path);

    write(path, `/* XPM */
static char *test_xpm[] = {
"2 2 2 1",
"R c #FF0000",
". c None",
"R.",
".R",
};
`);

    auto img = new XPMImage(path);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 2);

    auto rgba = new ubyte[2 * 2 * 4];
    assert(convertPixmap(img.xpmData, rgba, black));
    assert(rgba[0 .. 4] == [255, 0, 0, 255]);
    assert(rgba[4 .. 8][3] == 0);
}

unittest
{
    auto missing = new XPMImage("/nonexistent/path/does-not-exist.xpm");
    assert(missing.fail());
    assert(missing.w() < 0);
}
