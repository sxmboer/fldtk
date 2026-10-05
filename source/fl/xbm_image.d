/*
 * Ported from FL/Fl_XBM_Image.H + src/Fl_XBM_Image.cxx (FLTK 1.5.0): Fl_XBM_Image, an X Bitmap (XBM) file reader.
 * Milestone 3 of the fl.image port -- see fl.image's own top comment
 * for the overall staging.
 *
 * An XBM file is a tiny, valid C source fragment (the format X11's own
 * `bitmap` editor tool still emits): two `#define NAME_width N`/
 * `#define NAME_height N` lines, then a `static ... = { 0x.., 0x.., ...
 * };` byte array. Ported from `Fl_XBM_Image::Fl_XBM_Image()`, reading
 * the whole file via `std.file.readText()` and splitting into lines
 * rather than FLTK's byte-at-a-time `fgets()` loop (this port's
 * usual substitution, same as `fl.help_view`/`fl.file_browser`'s own
 * loaders) -- safe here since XBM files are plain ASCII text
 * throughout, unlike PNM's binary pixel formats (see fl.pnm_image's
 * row for why that one needs raw bytes instead).
 *
 * A failed read (missing file, malformed header, truncated data)
 * leaves the bitmap empty (`array` stays `null`, `w()`/`h()` stay `0`)
 * -- matching FLTK's own early-`return` behavior exactly (every
 * failure path there just stops, leaving whatever `Fl_Bitmap
 * ((const char*)0,0,0)`'s base construction already set).
 */
module fl.xbm_image;

import fl.bitmap : Bitmap;

class XBMImage : Bitmap
{
    this(string filename)
    {
        super(null, 0, 0);
        readXbm(filename);
    }

    private void readXbm(string filename)
    {
        import std.file : readText;
        import std.string : splitLines;

        string content;
        try
            content = readText(filename);
        catch (Exception)
            return;

        auto lines = content.splitLines();
        size_t lineIdx = 0;

        int[2] wh;
        foreach (i; 0 .. 2)
        {
            bool found = false;
            while (lineIdx < lines.length)
            {
                int val;
                if (parseDefine(lines[lineIdx++], val))
                {
                    wh[i] = val;
                    found = true;
                    break;
                }
            }
            if (!found) return;
        }

        while (lineIdx < lines.length && !startsWithStatic(lines[lineIdx])) lineIdx++;
        if (lineIdx >= lines.length) return;
        lineIdx++; // the "static ..." line itself carries no byte data

        if (wh[0] <= 0 || wh[1] <= 0) return;
        int n = ((wh[0] + 7) / 8) * wh[1];
        auto bits = new ubyte[n];
        int filled = 0;
        while (filled < n && lineIdx < lines.length)
            filled = parseHexBytes(lines[lineIdx++], bits, filled);
        if (filled < n) return; // truncated data -- stay empty/failed

        w(wh[0]);
        h(wh[1]);
        array = bits;
        hasData(true);
    }
}

/// Matches `sscanf(buffer, "#define %1023s %d", junk, &wh[i])`
/// requiring at least 2 matched items -- the macro name itself
/// (`junk` FLTK) is read and discarded, only the trailing integer
/// matters.
private bool parseDefine(string line, out int val)
{
    import std.string : split;
    import std.conv : to, ConvException;

    auto parts = line.split();
    if (parts.length < 3 || parts[0] != "#define") return false;
    try
        val = parts[2].to!int;
    catch (ConvException)
        return false;
    return true;
}

private bool startsWithStatic(string line)
{
    import std.string : startsWith;

    return line.startsWith("static ");
}

private int hexDigitOrInvalid(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 20;
}

/**
 * Scans line for comma-separated `0x..` hex byte tokens (optionally
 * preceded by whitespace, matching `sscanf(a," 0x%x",&t)`), appending
 * each successfully-parsed byte into bits starting at index filled.
 * Ported from the inner per-line scan loop in
 * `Fl_XBM_Image::Fl_XBM_Image()` -- a token that doesn't match `0x..`
 * (stray whitespace, a closing `};`, ...) is simply skipped, matching
 * FLTK's own "advance past the next comma regardless" behavior.
 */
private int parseHexBytes(string line, ubyte[] bits, int filled)
{
    size_t p = 0;
    while (filled < bits.length && p < line.length)
    {
        size_t q = p;
        while (q < line.length && (line[q] == ' ' || line[q] == '\t')) q++;
        if (q + 1 < line.length && line[q] == '0' && (line[q + 1] == 'x' || line[q + 1] == 'X'))
        {
            size_t hexStart = q + 2;
            size_t hexEnd = hexStart;
            uint val = 0;
            while (hexEnd < line.length && hexDigitOrInvalid(line[hexEnd]) <= 15)
            {
                val = (val << 4) | hexDigitOrInvalid(line[hexEnd]);
                hexEnd++;
            }
            if (hexEnd > hexStart) bits[filled++] = cast(ubyte) val;
        }
        while (p < line.length && line[p] != ',') p++;
        if (p < line.length) p++;
        else break;
    }
    return filled;
}

unittest
{
    // parseDefine()/parseHexBytes(): pure text parsing, no file I/O.
    int v;
    assert(parseDefine("#define foo_width 16", v) && v == 16);
    assert(parseDefine("#define foo_height 8", v) && v == 8);
    assert(!parseDefine("static char foo[] = {", v));

    ubyte[] bits = new ubyte[3];
    int filled = parseHexBytes("  0x01, 0xAB, 0xff, };", bits, 0);
    assert(filled == 3);
    assert(bits == [0x01, 0xAB, 0xFF]);
}

unittest
{
    // Real end-to-end file round trip via an isolated temp file --
    // same pattern as fl.file_browser's own loadDirectory() test.
    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-xbm-test-" ~ randomUUID().toString() ~ ".xbm");
    scope (exit) if (exists(path)) remove(path);

    // A 2px-wide, 1px-tall bitmap: one row, one byte, bit 0 set (left
    // pixel on, right pixel off) -- (2+7)/8 = 1 byte.
    write(path, "#define test_width 2\n#define test_height 1\n"
            ~ "static unsigned char test_bits[] = {\n   0x01 };\n");

    auto img = new XBMImage(path);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 1);
    assert(img.array == [0x01]);
}

unittest
{
    // Missing file / malformed header: stays empty, matches FLTK's
    // own early-return-on-failure behavior.
    auto missing = new XBMImage("/nonexistent/path/does-not-exist.xbm");
    assert(missing.fail());
    assert(missing.array.length == 0);
}
