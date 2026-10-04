/*
 * Ported from FL/Fl_PNM_Image.H + src/Fl_PNM_Image.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk): Fl_PNM_Image, a Portable Anymap (PNM: PBM/PGM/
 * PPM, formats P1-P6, plus XV's own P7 "3:3:2" thumbnail extension)
 * file reader. Milestone 3 of the fl.image port -- see fl.image's own
 * top comment for the overall staging.
 *
 * Unlike fl.xbm_image/fl.xpm_image (plain ASCII text throughout), a
 * PNM file's *header* (magic number, width, height, maxval, each
 * optionally interspersed with `#`-comments) is whitespace-delimited
 * ASCII, but formats 4-7's *pixel data* is raw binary immediately
 * following the header with no delimiter -- so this reader works over
 * a raw `ubyte[]` (via `std.file.read()`, not `readText()`/
 * `splitLines()`) with an explicit byte cursor, tracking exactly where
 * the header ends and the (possibly binary) pixel data begins, mirroring
 * FLTK's own `fgets()`-for-header/`getc()`-or-`fread()`-for-pixels
 * split but over an in-memory buffer instead of a live `FILE*`.
 *
 * A failed read reports FLTK's own specific error codes via
 * `ld()`/`fail()` (`errFileAccess` for a missing/unreadable file,
 * `errFormat` for a malformed header or a file too short for its own
 * claimed dimensions) rather than the generic `errNoImage` a bare
 * `RGBImage` failure would report -- ported by constructing via the
 * base `RGBImage` constructor first (which independently sets its own
 * `errMemoryAccess` sentinel on a too-short buffer, see that
 * constructor's own doc comment) and then, only on this reader's own
 * *earlier* failures (before any buffer even exists), overwriting
 * `ld()` with the more specific code -- matching `fail()`'s own
 * `w_<=0`-gated check, which always consults whatever `ld()` currently
 * holds.
 *
 * Not ported: `Fl_RGB_Image::max_size()`'s configurable "refuse to
 * load if the image would exceed this many bytes" safety cap -- a
 * rarely-tuned defensive limit (default "essentially infinite") that
 * would need its own small subsystem to port for one caller; skipped
 * the same way this port already skips other purely-defensive size
 * caps that don't matter for realistic inputs (e.g. `fl.draw`'s
 * skipped 16-bit-coordinate pre-clamping).
 */
module fl.pnm_image;

import fl.image : Image, RGBImage;

class PNMImage : RGBImage
{
    this(string filename)
    {
        auto r = readPnm(filename);
        super(r.bits, r.w, r.h, r.d);
        if (r.err != 0) ld(r.err);
    }
}

private struct PnmResult
{
    ubyte[] bits;
    int w, h, d;
    int err;
}

private bool isPnmSpace(ubyte c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

private bool isDigitByte(ubyte c)
{
    return c >= '0' && c <= '9';
}

private PnmResult readPnm(string filename)
{
    import std.file : read;

    ubyte[] data;
    try
        data = cast(ubyte[])(read(filename));
    catch (Exception)
        return PnmResult(null, 0, 0, 0, Image.errFileAccess);

    if (data.length < 2 || data[0] != 'P' || !isDigitByte(data[1]))
        return PnmResult(null, 0, 0, 0, Image.errFormat);
    int format = data[1] - '0';
    if (format < 1 || format > 7) return PnmResult(null, 0, 0, 0, Image.errFormat);

    size_t pos = 2;

    // Skips whitespace and `#`-to-end-of-line comments, then reads one
    // decimal integer -- matches FLTK's own comment/whitespace-
    // tolerant header-token scan exactly (the `while` loop in the
    // constructor that runs once per token: width, height, maxval).
    bool readInt(out int val)
    {
        for (;;)
        {
            while (pos < data.length && isPnmSpace(data[pos])) pos++;
            if (pos < data.length && data[pos] == '#')
            {
                while (pos < data.length && data[pos] != '\n') pos++;
                continue;
            }
            break;
        }
        if (pos >= data.length || !isDigitByte(data[pos])) return false;
        int v = 0;
        while (pos < data.length && isDigitByte(data[pos]))
        {
            v = v * 10 + (data[pos] - '0');
            pos++;
        }
        val = v;
        return true;
    }

    int w, h, maxval;
    if (!readInt(w) || !readInt(h) || w <= 0 || h <= 0)
        return PnmResult(null, 0, 0, 0, Image.errFormat);
    if (format == 1 || format == 4)
        maxval = 1;
    else if (!readInt(maxval) || maxval <= 0)
        return PnmResult(null, 0, 0, 0, Image.errFormat);
    // Exactly one separator byte follows the header before binary
    // pixel data begins (the PNM spec's own "single whitespace
    // character" requirement between the header and binary data) --
    // matches FLTK's own `fgets()`-based header scan, which always
    // lands the real file position at this exact spot for any binary
    // format (4 has no maxval token, but still needs this same skip
    // after its height token; 5-7 all read a maxval token first).
    // Formats 1-3 don't need it: they re-enter the same whitespace-
    // skipping readInt() scan for every value anyway.
    if ((format == 4 || format == 5 || format == 6 || format == 7)
        && pos < data.length && isPnmSpace(data[pos])) pos++;

    int d = (format == 1 || format == 2 || format == 4 || format == 5) ? 1 : 3;

    auto bits = new ubyte[w * h * d];
    size_t outIdx = 0;

    final switch (format)
    {
    case 1: // PBM ASCII
        for (int i = 0; i < w * h; i++)
        {
            int val;
            if (!readInt(val)) return PnmResult(null, 0, 0, 0, Image.errFormat);
            bits[outIdx++] = cast(ubyte)(255 * (1 - (val ? 1 : 0)));
        }
        break;

    case 2: // PGM ASCII
        for (int i = 0; i < w * h; i++)
        {
            int val;
            if (!readInt(val)) return PnmResult(null, 0, 0, 0, Image.errFormat);
            bits[outIdx++] = cast(ubyte)(255 * val / maxval);
        }
        break;

    case 3: // PPM ASCII
        for (int i = 0; i < w * h * 3; i++)
        {
            int val;
            if (!readInt(val)) return PnmResult(null, 0, 0, 0, Image.errFormat);
            bits[outIdx++] = cast(ubyte)(255 * val / maxval);
        }
        break;

    case 4: // PBM binary: packed bits, MSB first, 0=white/1=black
        for (int y = 0; y < h; y++)
        {
            ubyte b = 0;
            int bit = 0;
            for (int x = 0; x < w; x++)
            {
                if (bit == 0)
                {
                    if (pos >= data.length) return PnmResult(null, 0, 0, 0, Image.errFormat);
                    b = data[pos++];
                    bit = 8;
                }
                bits[outIdx++] = (b & 0x80) ? 0 : 255;
                b <<= 1;
                bit--;
            }
        }
        break;

    case 5: // PGM binary
    case 6: // PPM binary
        {
            int samples = w * h * d;
            if (maxval < 256)
            {
                if (pos + samples > data.length)
                    return PnmResult(null, 0, 0, 0, Image.errFormat);
                bits[0 .. samples] = data[pos .. pos + samples];
                pos += samples;
            }
            else
            {
                for (int i = 0; i < samples; i++)
                {
                    if (pos + 2 > data.length) return PnmResult(null, 0, 0, 0, Image.errFormat);
                    int val = (data[pos] << 8) | data[pos + 1];
                    pos += 2;
                    bits[outIdx++] = cast(ubyte)((255 * val) / maxval);
                }
            }
        }
        break;

    case 7: // XV thumbnail: 1 byte/pixel, packed 3:3:2 (R:G:B)
        for (int i = 0; i < w * h; i++)
        {
            if (pos >= data.length) return PnmResult(null, 0, 0, 0, Image.errFormat);
            ubyte byte_ = data[pos++];
            bits[outIdx++] = cast(ubyte)(255 * ((byte_ >> 5) & 7) / 7);
            bits[outIdx++] = cast(ubyte)(255 * ((byte_ >> 2) & 7) / 7);
            bits[outIdx++] = cast(ubyte)(255 * (byte_ & 3) / 3);
        }
        break;
    }

    return PnmResult(bits, w, h, d, 0);
}

unittest
{
    // ASCII PGM (P2): 2x1, maxval 255, values 0 and 255.
    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-pnm-test-" ~ randomUUID().toString() ~ ".pgm");
    scope (exit) if (exists(path)) remove(path);

    write(path, "P2\n# a comment\n2 1\n255\n0 255\n");

    auto img = new PNMImage(path);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 1 && img.d() == 1);
    assert(img.array == [0, 255]);
}

unittest
{
    // Binary PPM (P6): 2x1 RGB, maxval 255.
    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-pnm-test-" ~ randomUUID().toString() ~ ".ppm");
    scope (exit) if (exists(path)) remove(path);

    ubyte[] content = cast(ubyte[]) "P6\n2 1\n255\n".dup;
    content ~= [255, 0, 0, 0, 255, 0]; // red pixel, green pixel
    write(path, content);

    auto img = new PNMImage(path);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 1 && img.d() == 3);
    assert(img.array == [255, 0, 0, 0, 255, 0]);
}

unittest
{
    // Binary PBM (P4): 8x1, one packed byte, MSB first.
    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-pnm-test-" ~ randomUUID().toString() ~ ".pbm");
    scope (exit) if (exists(path)) remove(path);

    ubyte[] content = cast(ubyte[]) "P4\n8 1\n".dup;
    content ~= [0b1010_0000]; // leftmost 2 pixels: black, white, black, white...
    write(path, content);

    auto img = new PNMImage(path);
    assert(!img.fail());
    assert(img.w() == 8 && img.h() == 1 && img.d() == 1);
    // 1-bit = black = 0, 0-bit = white = 255
    assert(img.array == [0, 255, 0, 255, 255, 255, 255, 255]);
}

unittest
{
    // Failure modes: missing file (errFileAccess) and a malformed
    // header (errFormat) -- both surfaced via fail(), not just a
    // generic errNoImage.
    auto missing = new PNMImage("/nonexistent/path/does-not-exist.pnm");
    assert(missing.fail() == Image.errFileAccess);

    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-pnm-test-" ~ randomUUID().toString() ~ ".pnm");
    scope (exit) if (exists(path)) remove(path);
    write(path, "not a pnm file at all");

    auto bad = new PNMImage(path);
    assert(bad.fail() == Image.errFormat);
}
