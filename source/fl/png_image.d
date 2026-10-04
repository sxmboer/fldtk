/*
 * Ported from FL/Fl_PNG_Image.H + src/Fl_PNG_Image.cxx + src/fl_write_png.cxx
 * (FLTK 1.5.0, ~/Repositories/fltk): Fl_PNG_Image, a Portable Network
 * Graphics (PNG) file reader, plus the free fl_write_png() writer
 * functions.
 *
 * PNG decoding/encoding itself is adapted from Adam D. Ruppe's
 * `arsd.png` (~/Repositories/arsd/png.d, part of the `arsd` D utility
 * collection, Boost Software License 1.0 -- full text below, per that
 * license's own requirement to keep it attached to the source). Per
 * CLAUDE.md's "Deferred: external-library-backed features" section,
 * this resolves PNG's "write a small D-native decoder, or bind to
 * libpng" choice as neither -- arsd.png is already real, tested,
 * high-level D, and its low-level chunk/zlib/filter-reconstruction API is
 * *already* separated from the `arsd.color`-based `MemoryImage`
 * convenience layer its own high-level `readPng()`/`writePng()`
 * wrappers use -- exactly the shape needed to retarget onto
 * `fl.image.RGBImage` instead, without touching `arsd.color` at all.
 * Only that low-level, `MemoryImage`-free half of `png.d` (roughly its
 * first 1230 lines -- `PNG`/`Chunk`/`PngHeader`, `readPng()`/
 * `blankPNG()`/`addImageDatastreamToPng()`/`writePng(PNG*)`,
 * `getDatastream()`, `unfilter()`, `fetchPalette()`) is adapted here;
 * the second half of that file (a lazy, range-based streaming reader
 * for progressive/network loading, `LazyPngFile` and friends) has no
 * FLTK equivalent to serve and isn't used.
 *
 * `std.zlib` (Phobos's own zlib binding, linking the system `libz` --
 * see `dub.sdl`'s new `"z"` `libs` entry) does the actual DEFLATE/
 * INFLATE work, same as arsd.png's own `getDatastream()`/
 * `addImageDatastreamToPng()` already did -- PNG's compression *is*
 * zlib by spec, so every real decoder needs this somewhere; Phobos
 * already ships a binding, so there was never a "write raw DEFLATE
 * ourselves" option worth considering, just "link libz via Phobos" vs.
 * "link libz via a hand-rolled binding" -- the former is strictly less
 * code for the same result, and libz is an extremely stable, standard
 * system library (same category as X11/Xft, already linked here).
 *
 * Where this differs from a literal transliteration of arsd.png (not
 * bugs, deliberate adaptations to fit `Fl_RGB_Image`'s "already fully
 * expanded, no stored palette" shape and match FLTK `Fl_PNG_Image`'s
 * own exact channel-count semantics, since `Fl_RGB_Image` has no
 * equivalent of `arsd.color.IndexedImage`'s separately-stored palette):
 *  - `RGBImage.d()` (the channel count) matches FLTK's own
 *    `channels` calc in `Fl_PNG_Image::load_png_()` exactly (1 for
 *    plain greyscale, 2 for greyscale+alpha, 3 for truecolor/indexed
 *    without transparency, 4 for truecolor-with-alpha or
 *    indexed-with-a-tRNS-chunk) instead of arsd.png's own
 *    `convertPngData()`, which always expands grey/truecolor to a
 *    fixed 4-channel RGBA `TrueColorImage` layout and leaves indexed
 *    data as raw un-palette-applied index bytes (fine for arsd's own
 *    `IndexedImage`, which stores the palette separately -- not usable
 *    directly as `Fl_RGB_Image`'s already-expanded pixel data).
 *  - Indexed (`PLTE`) images are expanded through the resolved palette
 *    (`fetchPalette()`, ported closely -- it already folds a `tRNS`
 *    chunk's per-entry alpha into the palette's own `.a` field) into
 *    real RGB/RGBA pixels here, rather than staying as raw index bytes
 *    a caller would need a separate palette lookup for.
 *  - The nested `for` loop plus labeled `break loop` arsd.png's own
 *    `convertPngData()` uses to walk a bit-packed (sub-8-bit-depth)
 *    scanline collapses to a single `while` loop here (`expandScanline`
 *    below) -- a pure restructuring with identical per-pixel behavior,
 *    not a functional change; D has no equivalent readability problem
 *    to solve, this is just less to follow.
 *  - Known, deliberate gap vs. FLTK: `tRNS`-based single-color-key
 *    transparency for plain greyscale/truecolor (types 0/2) is NOT
 *    applied -- those load fully opaque. This is a real, narrower
 *    FLTK feature (`png_set_tRNS_to_alpha()` handles it for every
 *    color type, not just indexed) that's genuinely rare in practice
 *    (color-keyed transparency predates PNG's own alpha-channel types
 *    and fell out of common use once types 4/6 arrived) -- flagged
 *    here rather than silently dropped, and easy to add later if a
 *    real `.png` file ever needs it.
 *  - Interlaced (Adam7, `interlaceMethod != 0`) PNGs are NOT supported
 *    -- neither arsd.png's eager `imageFromPng()` path nor this
 *    adaptation deinterlaces; rejected with `errFormat` rather than
 *    silently producing a scrambled image. A real gap, not yet needed
 *    by any `.fl`/sample file in this project.
 *  - PNG write always emits filter-type 0 (None) per scanline, exactly
 *    matching arsd.png's own `addImageDatastreamToPng()` (no filter
 *    heuristic/minimum-sum-of-absolute-differences selection like
 *    libpng's default encoder) -- correct, just less compressed than
 *    an optimizing encoder.
 *  - `Fl_PNG_Image`'s private `Fl_ICO_Image`-only constructor (decoding
 *    a PNG-format icon resource embedded in a modern `.ico` file, at a
 *    byte offset with no leading file header) is not ported -- `fl.
 *    ico_image.ICOImage` doesn't support PNG-format icon resources at
 *    all yet, BMP-format only (see that module's own row).
 *
 * See `PORTING.md`'s `FL/Fl_PNG_Image.H` row for the full writeup.
 */
module fl.png_image;

import fl.image : Image, RGBImage;

// ---------------------------------------------------------------------
// Low-level PNG chunk structures and codec, adapted from arsd.png.
// ---------------------------------------------------------------------
//
// arsd.png itself: By Adam D. Ruppe, 2009-2010, released into the
// public domain. The wrapping `arsd` package as a whole is licensed
// Boost Software License 1.0 -- full text below, per that license's
// own requirement to keep it attached to the source.
//
// Boost Software License - Version 1.0 - August 17th, 2003
//
// Permission is hereby granted, free of charge, to any person or
// organization obtaining a copy of the software and accompanying
// documentation covered by this license (the "Software") to use,
// reproduce, display, distribute, execute, and transmit the Software,
// and to prepare derivative works of the Software, and to permit
// third-parties to whom the Software is furnished to do so, all
// subject to the following:
//
// The copyright notices in the Software and this entire statement,
// including the above license grant, this restriction and the
// following disclaimer, must be included in all copies of the
// Software, in whole or in part, and all derivative works of the
// Software, unless such copies or derivative works are solely in the
// form of machine-executable object code generated by a source code
// representation.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND
// NON-INFRINGEMENT. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR ANYONE
// DISTRIBUTING THE SOFTWARE BE LIABLE FOR ANY DAMAGES OR OTHER
// LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

private struct PngColor
{
    ubyte r, g, b;
    ubyte a = 255;
}

private struct Chunk
{
    uint size;
    ubyte[4] type;
    ubyte[] payload;
    uint checksum;

    const(char)[] stype() const { return cast(const(char)[]) type; }
}

private struct PngHeader
{
    uint width;
    uint height;
    ubyte depth = 8;
    ubyte type = 6;
    ubyte compressionMethod;
    ubyte filterMethod;
    ubyte interlaceMethod;
}

private struct PNG
{
    ubyte[8] magic;
    Chunk[] chunks;

    Chunk* getChunk(string what)
    {
        foreach (ref c; chunks) if (c.stype == what) return &c;
        throw new Exception("no such PNG chunk " ~ what);
    }

    Chunk* getChunkNullable(string what)
    {
        foreach (ref c; chunks) if (c.stype == what) return &c;
        return null;
    }
}

private enum PngType : ubyte
{
    greyscale = 0,
    truecolor = 2,
    indexed = 3,
    greyscaleWithAlpha = 4,
    truecolorWithAlpha = 6,
}

private immutable ubyte[8] pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

private uint updateCrc(uint crc, const(ubyte)[] buf)
{
    static immutable uint[256] crcTable = [0, 1996959894, 3993919788, 2567524794, 124634137, 1886057615, 3915621685, 2657392035, 249268274, 2044508324, 3772115230, 2547177864, 162941995, 2125561021, 3887607047, 2428444049, 498536548, 1789927666, 4089016648, 2227061214, 450548861, 1843258603, 4107580753, 2211677639, 325883990, 1684777152, 4251122042, 2321926636, 335633487, 1661365465, 4195302755, 2366115317, 997073096, 1281953886, 3579855332, 2724688242, 1006888145, 1258607687, 3524101629, 2768942443, 901097722, 1119000684, 3686517206, 2898065728, 853044451, 1172266101, 3705015759, 2882616665, 651767980, 1373503546, 3369554304, 3218104598, 565507253, 1454621731, 3485111705, 3099436303, 671266974, 1594198024, 3322730930, 2970347812, 795835527, 1483230225, 3244367275, 3060149565, 1994146192, 31158534, 2563907772, 4023717930, 1907459465, 112637215, 2680153253, 3904427059, 2013776290, 251722036, 2517215374, 3775830040, 2137656763, 141376813, 2439277719, 3865271297, 1802195444, 476864866, 2238001368, 4066508878, 1812370925, 453092731, 2181625025, 4111451223, 1706088902, 314042704, 2344532202, 4240017532, 1658658271, 366619977, 2362670323, 4224994405, 1303535960, 984961486, 2747007092, 3569037538, 1256170817, 1037604311, 2765210733, 3554079995, 1131014506, 879679996, 2909243462, 3663771856, 1141124467, 855842277, 2852801631, 3708648649, 1342533948, 654459306, 3188396048, 3373015174, 1466479909, 544179635, 3110523913, 3462522015, 1591671054, 702138776, 2966460450, 3352799412, 1504918807, 783551873, 3082640443, 3233442989, 3988292384, 2596254646, 62317068, 1957810842, 3939845945, 2647816111, 81470997, 1943803523, 3814918930, 2489596804, 225274430, 2053790376, 3826175755, 2466906013, 167816743, 2097651377, 4027552580, 2265490386, 503444072, 1762050814, 4150417245, 2154129355, 426522225, 1852507879, 4275313526, 2312317920, 282753626, 1742555852, 4189708143, 2394877945, 397917763, 1622183637, 3604390888, 2714866558, 953729732, 1340076626, 3518719985, 2797360999, 1068828381, 1219638859, 3624741850, 2936675148, 906185462, 1090812512, 3747672003, 2825379669, 829329135, 1181335161, 3412177804, 3160834842, 628085408, 1382605366, 3423369109, 3138078467, 570562233, 1426400815, 3317316542, 2998733608, 733239954, 1555261956, 3268935591, 3050360625, 752459403, 1541320221, 2607071920, 3965973030, 1969922972, 40735498, 2617837225, 3943577151, 1913087877, 83908371, 2512341634, 3803740692, 2075208622, 213261112, 2463272603, 3855990285, 2094854071, 198958881, 2262029012, 4057260610, 1759359992, 534414190, 2176718541, 4139329115, 1873836001, 414664567, 2282248934, 4279200368, 1711684554, 285281116, 2405801727, 4167216745, 1634467795, 376229701, 2685067896, 3608007406, 1308918612, 956543938, 2808555105, 3495958263, 1231636301, 1047427035, 2932959818, 3654703836, 1088359270, 936918000, 2847714899, 3736837829, 1202900863, 817233897, 3183342108, 3401237130, 1404277552, 615818150, 3134207493, 3453421203, 1423857449, 601450431, 3009837614, 3294710456, 1567103746, 711928724, 3020668471, 3272380065, 1510334235, 755167117];

    uint c = crc;
    foreach (b; buf) c = crcTable[(c ^ b) & 0xff] ^ (c >> 8);
    return c;
}

private uint pngCrc(string chunkType, const(ubyte)[] buf)
{
    uint c = updateCrc(0xffff_ffff, cast(const(ubyte)[]) chunkType);
    return updateCrc(c, buf) ^ 0xffff_ffff;
}

private PNG* readPng(const(ubyte)[] data)
{
    if (data.length < 8) throw new Exception("not a PNG, too short");
    auto p = new PNG;
    p.magic[] = data[0 .. 8];
    if (p.magic != pngMagic) throw new Exception("not a PNG, bad magic");

    size_t pos = 8;
    while (pos < data.length && data.length - pos >= 12)
    {
        Chunk n;
        n.size = (cast(uint) data[pos] << 24) | (cast(uint) data[pos + 1] << 16)
            | (cast(uint) data[pos + 2] << 8) | data[pos + 3];
        pos += 4;
        n.type[] = data[pos .. pos + 4];
        pos += 4;
        if (pos + n.size > data.length) throw new Exception("malformed PNG: chunk longer than data");
        n.payload = data[pos .. pos + n.size].dup;
        pos += n.size;
        n.checksum = (cast(uint) data[pos] << 24) | (cast(uint) data[pos + 1] << 16)
            | (cast(uint) data[pos + 2] << 8) | data[pos + 3];
        pos += 4;
        p.chunks ~= n;
        if (n.type[] == "IEND") break;
    }
    return p;
}

private PngHeader getHeader(PNG* p)
{
    auto data = p.getChunk("IHDR").payload;
    if (data.length < 13) throw new Exception("malformed PNG: IHDR too short");
    PngHeader h;
    h.width = (cast(uint) data[0] << 24) | (cast(uint) data[1] << 16) | (cast(uint) data[2] << 8) | data[3];
    h.height = (cast(uint) data[4] << 24) | (cast(uint) data[5] << 16) | (cast(uint) data[6] << 8) | data[7];
    h.depth = data[8];
    h.type = data[9];
    h.compressionMethod = data[10];
    h.filterMethod = data[11];
    h.interlaceMethod = data[12];
    return h;
}

private ubyte[] getDatastream(PNG* p)
{
    import std.zlib : uncompress;
    ubyte[] compressed;
    foreach (c; p.chunks) if (c.stype == "IDAT") compressed ~= c.payload;
    return cast(ubyte[]) uncompress(compressed);
}

private PngColor[] fetchPalette(PNG* p)
{
    PngColor[] colors;

    auto header = getHeader(p);
    if (header.type == PngType.greyscale)
    {
        colors.length = 256;
        foreach (i; 0 .. 256) colors[i] = PngColor(cast(ubyte) i, cast(ubyte) i, cast(ubyte) i);
        return colors;
    }

    auto palette = p.getChunk("PLTE");
    auto alpha = p.getChunkNullable("tRNS");
    colors.length = palette.size / 3;
    foreach (i; 0 .. colors.length)
    {
        colors[i].r = palette.payload[i * 3 + 0];
        colors[i].g = palette.payload[i * 3 + 1];
        colors[i].b = palette.payload[i * 3 + 2];
        colors[i].a = (alpha !is null && i < alpha.size) ? alpha.payload[i] : 255;
    }
    return colors;
}

private ubyte paethPredictor(ubyte a, ubyte b, ubyte c)
{
    import std.math : abs;
    int p = cast(int) a + b - c;
    auto pa = abs(p - a);
    auto pb = abs(p - b);
    auto pc = abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

/// Png files apply a per-scanline filter to aid compression; this
/// undoes that as the data is loaded. Ported verbatim from arsd.png's
/// own `unfilter()`.
private immutable(ubyte)[] unfilter(ubyte filterType, const(ubyte)[] data, const(ubyte)[] previousLine, int bpp)
{
    import std.exception : assumeUnique;

    final switch (filterType)
    {
        case 0:
            return data.idup;
        case 1:
        {
            auto arr = data.dup;
            foreach (i; cast(size_t) bpp .. arr.length) arr[i] += arr[i - bpp];
            return assumeUnique(arr);
        }
        case 2:
        {
            auto arr = data.dup;
            if (previousLine.length) foreach (i; 0 .. arr.length) arr[i] += previousLine[i];
            return assumeUnique(arr);
        }
        case 3:
        {
            auto arr = data.dup;
            foreach (i; 0 .. arr.length)
            {
                int left = i < bpp ? 0 : arr[i - bpp];
                int above = previousLine.length ? previousLine[i] : 0;
                arr[i] += cast(ubyte)((left + above) / 2);
            }
            return assumeUnique(arr);
        }
        case 4:
        {
            auto arr = data.dup;
            foreach (i; 0 .. arr.length)
            {
                ubyte left = i < bpp ? 0 : arr[i - bpp];
                ubyte above = i < previousLine.length ? previousLine[i] : 0;
                ubyte upperLeft = i < bpp ? 0 : (i < previousLine.length ? previousLine[i - bpp] : 0);
                arr[i] += paethPredictor(left, above, upperLeft);
            }
            return assumeUnique(arr);
        }
    }
}

private int bytesPerPixel(PngHeader h)
{
    int bitsPerChannel = h.depth;
    int bitsPerPixel = bitsPerChannel;
    if ((h.type & 2) && !(h.type & 1)) bitsPerPixel *= 3; // in color, no palette
    if (h.type & 4) bitsPerPixel += bitsPerChannel; // alpha channel present in the datastream
    return (bitsPerPixel + 7) / 8;
}

/// Channels actually present in the compressed datastream per pixel --
/// distinct from `outputChannels()` below, which additionally accounts
/// for a palette's `tRNS`-derived alpha (never part of the datastream
/// itself for an indexed image).
private int channelsInStream(ubyte type)
{
    switch (type)
    {
        case PngType.greyscale: return 1;
        case PngType.truecolor: return 3;
        case PngType.indexed: return 1;
        case PngType.greyscaleWithAlpha: return 2;
        case PngType.truecolorWithAlpha: return 4;
        default: throw new Exception("unsupported PNG color type");
    }
}

private int bytesPerScanline(PngHeader h)
{
    long bits = cast(long) h.width * channelsInStream(h.type) * h.depth;
    return cast(int)((bits + 7) / 8);
}

/// The channel count `RGBImage.d()` reports -- matches FLTK
/// `Fl_PNG_Image::load_png_()`'s own `channels` calculation exactly
/// (see this module's own top comment for the one narrow case, plain
/// grey/truecolor `tRNS` color-keying, this doesn't cover).
private int outputChannels(ubyte type, bool hasTrns)
{
    switch (type)
    {
        case PngType.greyscale: return 1;
        case PngType.truecolor: return 3;
        case PngType.indexed: return hasTrns ? 4 : 3;
        case PngType.greyscaleWithAlpha: return 2;
        case PngType.truecolorWithAlpha: return 4;
        default: throw new Exception("unsupported PNG color type");
    }
}

/// Expands one already-unfiltered scanline into `outChannels`-byte-per-
/// pixel output, resolving indexed pixels through `palette`. Adapted
/// from arsd.png's own `convertPngData()` -- see this module's top
/// comment for exactly what changed and why.
private void expandScanline(ubyte type, ubyte depth, const(ubyte)[] data, int width,
    int outChannels, const(PngColor)[] palette, ubyte[] idata, ref size_t idataIdx)
{
    ubyte consumeOne()
    {
        ubyte r = data[0];
        data = data[1 .. $];
        return r;
    }

    void acceptPixel(ubyte p)
    {
        if (type == PngType.indexed)
        {
            auto c = palette[p];
            idata[idataIdx++] = c.r;
            idata[idataIdx++] = c.g;
            idata[idataIdx++] = c.b;
            if (outChannels == 4) idata[idataIdx++] = c.a;
            return;
        }

        // greyscale / greyscale+alpha
        if (depth == 1) p = p ? 0xff : 0;
        else if (depth == 2) { p |= p << 2; p |= p << 4; }
        else if (depth == 4) p |= p << 4;
        idata[idataIdx++] = p;
        if (type == PngType.greyscaleWithAlpha) idata[idataIdx++] = consumeOne();
    }

    int pixel = 0;
    while (pixel < width)
    {
        if (type == PngType.truecolor || type == PngType.truecolorWithAlpha)
        {
            // Truecolor(+alpha) samples are always 8 or 16 bits each,
            // never sub-8-bit-packed -- one pixel per iteration.
            if (depth == 8)
            {
                idata[idataIdx++] = consumeOne();
                idata[idataIdx++] = consumeOne();
                idata[idataIdx++] = consumeOne();
                if (type == PngType.truecolorWithAlpha) idata[idataIdx++] = consumeOne();
            }
            else // depth == 16: keep the high byte only (matches FLTK's 16->8 strip)
            {
                idata[idataIdx++] = consumeOne(); consumeOne();
                idata[idataIdx++] = consumeOne(); consumeOne();
                idata[idataIdx++] = consumeOne(); consumeOne();
                if (type == PngType.truecolorWithAlpha) { idata[idataIdx++] = consumeOne(); consumeOne(); }
            }
            pixel++;
            continue;
        }

        // greyscale / greyscale+alpha / indexed: may be sub-8-bit packed.
        auto b = consumeOne();
        final switch (depth)
        {
            case 1:
                acceptPixel((b >> 7) & 0x01); if (++pixel >= width) break;
                acceptPixel((b >> 6) & 0x01); if (++pixel >= width) break;
                acceptPixel((b >> 5) & 0x01); if (++pixel >= width) break;
                acceptPixel((b >> 4) & 0x01); if (++pixel >= width) break;
                acceptPixel((b >> 3) & 0x01); if (++pixel >= width) break;
                acceptPixel((b >> 2) & 0x01); if (++pixel >= width) break;
                acceptPixel((b >> 1) & 0x01); if (++pixel >= width) break;
                acceptPixel(b & 0x01);
                pixel++;
                break;
            case 2:
                acceptPixel((b >> 6) & 0x03); if (++pixel >= width) break;
                acceptPixel((b >> 4) & 0x03); if (++pixel >= width) break;
                acceptPixel((b >> 2) & 0x03); if (++pixel >= width) break;
                acceptPixel(b & 0x03);
                pixel++;
                break;
            case 4:
                acceptPixel((b >> 4) & 0x0f); if (++pixel >= width) break;
                acceptPixel(b & 0x0f);
                pixel++;
                break;
            case 8:
                acceptPixel(b);
                pixel++;
                break;
            case 16:
                acceptPixel(b);
                consumeOne(); // discard low byte, matching FLTK's/arsd's 16->8 truncation
                pixel++;
                break;
        }
    }
}

private ubyte[] decodePngPixels(PNG* p, out int width, out int height, out int channels)
{
    PngHeader h = getHeader(p);
    if (h.compressionMethod != 0) throw new Exception("unsupported PNG compression method");
    if (h.filterMethod != 0) throw new Exception("unsupported PNG filter method");
    if (h.interlaceMethod != 0) throw new Exception("interlaced PNG not supported");
    if (h.width == 0 || h.height == 0) throw new Exception("empty PNG");

    width = cast(int) h.width;
    height = cast(int) h.height;

    PngColor[] palette;
    bool hasTrns;
    if (h.type == PngType.indexed)
    {
        palette = fetchPalette(p);
        hasTrns = p.getChunkNullable("tRNS") !is null;
    }

    channels = outputChannels(h.type, hasTrns);

    auto idata = new ubyte[cast(size_t) width * height * channels];
    size_t idataIdx;

    auto raw = getDatastream(p);
    int lineBytes = bytesPerScanline(h);
    int bpp = bytesPerPixel(h);

    immutable(ubyte)[] previousLine;
    size_t pos;
    foreach (y; 0 .. height)
    {
        if (pos + 1 + lineBytes > raw.length) throw new Exception("truncated PNG image data");
        ubyte filterType = raw[pos];
        auto lineData = raw[pos + 1 .. pos + 1 + lineBytes];
        pos += 1 + lineBytes;

        auto unfiltered = unfilter(filterType, lineData, previousLine, bpp);
        previousLine = unfiltered;

        expandScanline(h.type, h.depth, unfiltered, width, channels, palette, idata, idataIdx);
    }

    return idata;
}

private PNG* blankPng(PngHeader h)
{
    auto p = new PNG;
    p.magic = pngMagic;

    Chunk c;
    c.type = ['I', 'H', 'D', 'R'];
    c.payload.length = 13;
    size_t pos = 0;
    c.payload[pos++] = cast(ubyte)(h.width >> 24);
    c.payload[pos++] = cast(ubyte)(h.width >> 16);
    c.payload[pos++] = cast(ubyte)(h.width >> 8);
    c.payload[pos++] = cast(ubyte)(h.width);
    c.payload[pos++] = cast(ubyte)(h.height >> 24);
    c.payload[pos++] = cast(ubyte)(h.height >> 16);
    c.payload[pos++] = cast(ubyte)(h.height >> 8);
    c.payload[pos++] = cast(ubyte)(h.height);
    c.payload[pos++] = h.depth;
    c.payload[pos++] = h.type;
    c.payload[pos++] = h.compressionMethod;
    c.payload[pos++] = h.filterMethod;
    c.payload[pos++] = h.interlaceMethod;
    c.size = 13;
    c.checksum = pngCrc("IHDR", c.payload);
    p.chunks ~= c;
    return p;
}

/// Filters (always type 0, None -- see this module's own top comment)
/// and zlib-compresses `data` into a single IDAT chunk, then appends
/// IEND. `data` must already be the tightly-packed datastream matching
/// `png.chunks`' own IHDR (see `channelsInStream()`/depth).
private void addImageDatastreamToPng(const(ubyte)[] data, PNG* png)
{
    import std.zlib : compress;

    PngHeader h = getHeader(png);
    int multiplier = channelsInStream(h.type);
    size_t bytesPerLine = cast(size_t) h.width * multiplier * h.depth / 8;
    if ((h.width * multiplier * h.depth) % 8 != 0) bytesPerLine += 1;

    ubyte[] output;
    size_t pos = 0;
    while (pos + bytesPerLine <= data.length)
    {
        output ~= 0; // filter type: None
        output ~= data[pos .. pos + bytesPerLine];
        pos += bytesPerLine;
    }

    Chunk dat;
    dat.type = ['I', 'D', 'A', 'T'];
    auto com = cast(ubyte[]) compress(output);
    dat.size = cast(uint) com.length;
    dat.payload = com;
    dat.checksum = pngCrc("IDAT", dat.payload);
    png.chunks ~= dat;

    Chunk end;
    end.type = ['I', 'E', 'N', 'D'];
    end.checksum = pngCrc("IEND", end.payload);
    png.chunks ~= end;
}

private ubyte[] serializePng(PNG* p)
{
    ubyte[] a;
    a.length = 8;
    foreach (c; p.chunks) a.length += c.size + 12;

    a[0 .. 8] = p.magic[];
    size_t pos = 8;
    foreach (c; p.chunks)
    {
        a[pos++] = cast(ubyte)(c.size >> 24);
        a[pos++] = cast(ubyte)(c.size >> 16);
        a[pos++] = cast(ubyte)(c.size >> 8);
        a[pos++] = cast(ubyte)(c.size);

        a[pos .. pos + 4] = c.type[];
        pos += 4;
        a[pos .. pos + c.size] = c.payload[0 .. c.size];
        pos += c.size;

        a[pos++] = cast(ubyte)(c.checksum >> 24);
        a[pos++] = cast(ubyte)(c.checksum >> 16);
        a[pos++] = cast(ubyte)(c.checksum >> 8);
        a[pos++] = cast(ubyte)(c.checksum);
    }
    return a;
}

// ---------------------------------------------------------------------
// fl.image integration: PngImage (Fl_PNG_Image) and writePng().
// ---------------------------------------------------------------------

/// Ported from `Fl_PNG_Image` (`FL/Fl_PNG_Image.H` + `src/
/// Fl_PNG_Image.cxx`) -- a PNG file/buffer reader, decoding into an
/// already-expanded `RGBImage` pixel buffer. See this module's own top
/// comment for the decoder's origin and the specific, documented gaps
/// (no interlacing, no grey/truecolor tRNS color-keying) vs. FLTK.
class PngImage : RGBImage
{
    this(string filename)
    {
        super(null, 0, 0);
        import std.file : read;

        ubyte[] content;
        try
            content = cast(ubyte[]) read(filename);
        catch (Exception)
        {
            ld(errFileAccess);
            return;
        }
        loadPng(content);
    }

    /// Loads a PNG image from an in-memory buffer -- e.g. data embedded
    /// at compile time via Fluid or similar. `namePng` is unused by this
    /// port, matching `fl.bmp_image.BMPImage`'s own equivalent
    /// constructor and its own doc comment on why.
    this(string namePng, const(ubyte)[] buffer)
    {
        super(null, 0, 0);
        loadPng(buffer);
    }

    private void loadPng(const(ubyte)[] data)
    {
        int width, height, channels;
        ubyte[] pixels;
        try
        {
            auto p = readPng(data);
            pixels = decodePngPixels(p, width, height, channels);
        }
        catch (Exception)
        {
            ld(errFormat);
            return;
        }

        array = pixels;
        w(width);
        h(height);
        d(channels);
        ld(0);
        hasData(true);
    }
}

private PngType pngTypeForDepth(int d)
{
    switch (d)
    {
        case 1: return PngType.greyscale;
        case 2: return PngType.greyscaleWithAlpha;
        case 4: return PngType.truecolorWithAlpha;
        default: return PngType.truecolor;
    }
}

/**
 * Encodes a raw pixel buffer as PNG-format bytes in memory, with no
 * file involved. Factored out of `writePng()` below (which now just
 * writes this function's result to a file) so an in-memory consumer has
 * a real entry point too -- `fl.svg_file_surface.SvgGraphicsDriver.
 * drawImage()`/`drawBitmap()` base64-encodes this directly into a
 * `data:image/png;base64,...` URI, with no temp file of its own.
 *
 * `d`/`ld` mean exactly what they mean on `writePng()` -- see that
 * function's own doc comment.
 */
ubyte[] encodePngBytes(const(ubyte)[] pixels, int w, int h, int d = 3, int ld = 0)
{
    if (ld == 0) ld = w * d;

    PngHeader header;
    header.width = w;
    header.height = h;
    header.type = pngTypeForDepth(d);
    header.depth = 8;

    const(ubyte)[] packed = pixels;
    if (ld != w * d)
    {
        auto tmp = new ubyte[w * d * h];
        foreach (row; 0 .. h)
            tmp[row * w * d .. (row + 1) * w * d] = pixels[row * ld .. row * ld + w * d];
        packed = tmp;
    }

    auto png = blankPng(header);
    addImageDatastreamToPng(packed, png);
    return serializePng(png);
}

/**
 * Writes a raw pixel buffer to a PNG file. Ported from
 * `fl_write_png(const char*, const unsigned char*, int, int, int, int)`
 * (`src/fl_write_png.cxx`) -- FLTK's separate `const char*`
 * overload collapses into this one D `const(ubyte)[]` overload, same
 * substitution used throughout this port for a raw-bytes parameter.
 *
 * `d` is the channel count (1 = grey, 2 = grey+alpha, 3 = RGB, 4 =
 * RGBA); `ld` is the row stride in bytes, `0` meaning tightly packed
 * (`w * d`), matching FLTK exactly.
 *
 * Returns 0 on success, -2 on a file-open/write failure -- matching
 * FLTK's own return codes; FLTK's `-1` ("png or zlib library
 * not available") never applies here, this port always has both.
 */
int writePng(string filename, const(ubyte)[] pixels, int w, int h, int d = 3, int ld = 0)
{
    auto bytes = encodePngBytes(pixels, w, h, d, ld);

    try
    {
        import std.file : write;
        write(filename, bytes);
    }
    catch (Exception)
    {
        return -2;
    }
    return 0;
}

/// ditto -- ported from `fl_write_png(const char*, Fl_RGB_Image*)`.
int writePng(string filename, RGBImage img)
{
    return writePng(filename, img.array, img.dataW(), img.dataH(), img.d(), img.ld());
}

// ---------------------------------------------------------------------
// Tests -- pure data processing, no X server needed (same reasoning as
// fl.bmp_image's own unittest coverage).
// ---------------------------------------------------------------------

unittest
{
    // Round-trip a small truecolor-with-alpha image entirely in memory,
    // via the private encode helpers directly (blankPng()/
    // addImageDatastreamToPng()/serializePng()) rather than writePng()
    // (that overload's own file-I/O path is covered separately below).
    ubyte[] pixels = [
        255, 0, 0, 255, 0, 255, 0, 128,
        0, 0, 255, 64, 255, 255, 255, 0,
    ];

    PngHeader h;
    h.width = 2;
    h.height = 2;
    h.type = PngType.truecolorWithAlpha;
    h.depth = 8;
    auto png = blankPng(h);
    addImageDatastreamToPng(pixels, png);
    auto bytes = serializePng(png);

    auto img = new PngImage("test", bytes);
    assert(img.fail() == 0);
    assert(img.w() == 2);
    assert(img.h() == 2);
    assert(img.d() == 4);
    assert(img.array == pixels);
}

unittest
{
    // Plain truecolor (no alpha) -- d() should come back 3, not 4.
    ubyte[] pixels = [
        10, 20, 30, 40, 50, 60,
        70, 80, 90, 100, 110, 120,
    ];

    PngHeader h;
    h.width = 2;
    h.height = 2;
    h.type = PngType.truecolor;
    h.depth = 8;
    auto png = blankPng(h);
    addImageDatastreamToPng(pixels, png);
    auto bytes = serializePng(png);

    auto img = new PngImage("test", bytes);
    assert(img.fail() == 0);
    assert(img.d() == 3);
    assert(img.array == pixels);
}

unittest
{
    // Plain greyscale, 1 bit per pixel, width not a multiple of 8 --
    // exercises expandScanline()'s early-break padding-bit handling.
    // 5 pixels: 1,0,1,1,0 -> byte 0b1011_0xxx (0xB0, padding bits don't
    // matter) per row, 3 rows.
    ubyte[] rawBits = [0xB0, 0xB0, 0xB0];

    PngHeader h;
    h.width = 5;
    h.height = 3;
    h.type = PngType.greyscale;
    h.depth = 1;
    auto png = blankPng(h);
    addImageDatastreamToPng(rawBits, png);
    auto bytes = serializePng(png);

    auto img = new PngImage("test", bytes);
    assert(img.fail() == 0);
    assert(img.w() == 5 && img.h() == 3);
    assert(img.d() == 1);
    ubyte[] expectedRow = [255, 0, 255, 255, 0];
    assert(img.array[0 .. 5] == expectedRow);
    assert(img.array[5 .. 10] == expectedRow);
    assert(img.array[10 .. 15] == expectedRow);
}

unittest
{
    // Indexed (paletted), no tRNS -> d() == 3, resolved through the
    // real palette.
    ubyte[] indices = [0, 1, 1, 0];

    PngHeader h;
    h.width = 2;
    h.height = 2;
    h.type = PngType.indexed;
    h.depth = 8;
    auto png = blankPng(h);

    Chunk palette;
    palette.type = ['P', 'L', 'T', 'E'];
    palette.payload = [10, 20, 30, 200, 210, 220]; // index 0, index 1
    palette.size = cast(uint) palette.payload.length;
    palette.checksum = pngCrc("PLTE", palette.payload);
    png.chunks = png.chunks[0 .. 1] ~ palette ~ png.chunks[1 .. $];

    addImageDatastreamToPng(indices, png);
    auto bytes = serializePng(png);

    auto img = new PngImage("test", bytes);
    assert(img.fail() == 0);
    assert(img.d() == 3);
    ubyte[] expected = [
        10, 20, 30, 200, 210, 220,
        200, 210, 220, 10, 20, 30,
    ];
    assert(img.array == expected);
}

unittest
{
    // Indexed with a tRNS chunk -> d() == 4, alpha resolved per index.
    ubyte[] indices = [0, 1];

    PngHeader h;
    h.width = 2;
    h.height = 1;
    h.type = PngType.indexed;
    h.depth = 8;
    auto png = blankPng(h);

    Chunk palette;
    palette.type = ['P', 'L', 'T', 'E'];
    palette.payload = [10, 20, 30, 40, 50, 60];
    palette.size = cast(uint) palette.payload.length;
    palette.checksum = pngCrc("PLTE", palette.payload);

    Chunk trns;
    trns.type = ['t', 'R', 'N', 'S'];
    trns.payload = [0, 255]; // index 0 fully transparent, index 1 opaque
    trns.size = cast(uint) trns.payload.length;
    trns.checksum = pngCrc("tRNS", trns.payload);

    png.chunks = png.chunks[0 .. 1] ~ palette ~ trns ~ png.chunks[1 .. $];

    addImageDatastreamToPng(indices, png);
    auto bytes = serializePng(png);

    auto img = new PngImage("test", bytes);
    assert(img.fail() == 0);
    assert(img.d() == 4);
    ubyte[] expected = [10, 20, 30, 0, 40, 50, 60, 255];
    assert(img.array == expected);
}

unittest
{
    // Malformed input (bad magic) reports errFormat, doesn't throw.
    auto img = new PngImage("bad", cast(const(ubyte)[]) [1, 2, 3, 4]);
    assert(img.fail() == Image.errFormat);
}

unittest
{
    // A missing file reports errFileAccess, doesn't throw.
    auto img = new PngImage("/nonexistent/path/does-not-exist.png");
    assert(img.fail() == Image.errFileAccess);
}

unittest
{
    // writePng()'s own file-I/O path, including the ld != w*d
    // (padded-row) repacking branch -- round-tripped through a real
    // temp file, then read back via PngImage's filename constructor.
    import std.file : tempDir, remove, exists;
    import std.path : buildPath;

    // 2x2 RGB, row stride padded to 8 bytes (2 bytes of garbage after
    // each 6-byte row).
    ubyte[] padded = [
        1, 2, 3, 4, 5, 6, 0, 0,
        7, 8, 9, 10, 11, 12, 0, 0,
    ];
    auto path = buildPath(tempDir(), "fldtk_png_image_test.png");
    scope (exit) if (exists(path)) remove(path);

    assert(writePng(path, padded, 2, 2, 3, 8) == 0);

    auto img = new PngImage(path);
    assert(img.fail() == 0);
    assert(img.w() == 2 && img.h() == 2 && img.d() == 3);
    ubyte[] expected = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    assert(img.array == expected);
}
