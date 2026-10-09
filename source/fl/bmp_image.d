/*
 * Ported from FL/Fl_BMP_Image.H + src/Fl_BMP_Image.cxx (FLTK 1.5.0): Fl_BMP_Image, a Windows Bitmap (BMP) file
 * reader. No external library needed -- BMP pixel data is either
 * uncompressed or uses a simple run-length scheme (RLE4/RLE8) FLTK
 * decodes itself, unlike JPEG/PNG/GIF's real compression codecs (see
 * CONVENTIONS.md's "Where this port intentionally exceeds FLTK" section
 * for why those, and SVG, are deliberately still out of scope).
 *
 * Reads the whole file into memory via `std.file.read()` and walks it
 * with an explicit byte cursor (the private `ByteReader` struct below)
 * rather than porting FLTK's own dual file-or-memory
 * `Fl_Image_Reader` helper class (`src/Fl_Image_Reader.h/.cxx`, shared
 * with `Fl_GIF_Image`, not ported here) -- this port's now-established
 * convention (matching `fl.pnm_image`'s own cursor-based reader) for
 * any format needing raw binary access, rather than the
 * `readText()`/`splitLines()` a purely-ASCII format like XBM/XPM can
 * use.
 *
 * `loadBmp()` (the real decoder, `protected` so `fl.ico_image.ICOImage`
 * -- a genuine subclass, embedded .ico bitmap resources being BMP data
 * in all but their missing outer BITMAPFILEHEADER -- can call it
 * directly with the width/height that file format already supplies)
 * handles every depth FLTK's own decoder does: 1-bit, 4-bit and
 * 8-bit paletted (both plain and RLE4/RLE8-compressed), 16-bit
 * (5:5:5 and 5:6:5 packed RGB), 24-bit RGB, and 32-bit RGBA, plus the
 * 1-bit-alpha-mask-following-the-pixel-data heuristic FLTK's own
 * decoder uses for older icon-style BMPs (`havemask`).
 *
 * Not ported: `Fl_RGB_Image::max_size()`'s configurable safety cap --
 * same documented, minor skip already established in `fl.pnm_image`'s
 * own row/module comment, for the same reason (a rarely-tuned
 * defensive limit not worth a whole small subsystem for one more
 * caller).
 */
module fl.bmp_image;

import fl.image : Image, RGBImage;

/// A little-endian byte-cursor reader over an in-memory buffer --
/// this port's simplified stand-in for FLTK's `Fl_Image_Reader`
/// (see the module's own top comment for why the file/memory dual-mode
/// split isn't needed here).
package(fl) struct ByteReader
{
    const(ubyte)[] data;
    size_t pos;
    bool error;

    ubyte readByte()
    {
        if (pos >= data.length)
        {
            error = true;
            return 0;
        }
        return data[pos++];
    }

    ushort readWord()
    {
        uint lo = readByte();
        uint hi = readByte();
        return cast(ushort)(lo | (hi << 8));
    }

    uint readDword()
    {
        uint b0 = readByte();
        uint b1 = readByte();
        uint b2 = readByte();
        uint b3 = readByte();
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    }

    int readLong() { return cast(int) readDword(); }

    void seek(size_t n)
    {
        pos = n;
        if (pos > data.length) error = true;
    }

    void skip(size_t n) { seek(pos + n); }
}

class BMPImage : RGBImage
{
    /// Empty-shell constructor for fl.ico_image.ICOImage's use only --
    /// an embedded .ico bitmap resource has no filename or standalone
    /// buffer of its own to hand to either public constructor below,
    /// just a slice of the already-open .ico file/buffer it parses
    /// directly via loadBmp().
    protected this()
    {
        super(null, 0, 0);
    }

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
        auto rdr = ByteReader(content, 0, false);
        loadBmp(rdr);
    }

    /// Loads a BMP image from an in-memory buffer -- e.g. data
    /// embedded at compile time via Fluid or similar. `imagename` is
    /// unused by this port (FLTK's own equivalent parameter exists
    /// only so the loaded image can also be registered under that name
    /// in `Fl_Shared_Image`'s pool, which this constructor doesn't do
    /// either -- go through `fl.shared_image.SharedImage.getFromRgb()`
    /// for that if needed).
    this(string imagename, const(ubyte)[] data)
    {
        super(null, 0, 0);
        auto rdr = ByteReader(data, 0, false);
        loadBmp(rdr);
    }

    /**
     * The real decoder, ported line-for-line from `Fl_BMP_Image::
     * load_bmp_()`. `icoHeight`/`icoWidth` are only set by
     * `fl.ico_image.ICOImage`, when decoding a bitmap resource
     * embedded in a `.ico` file: that format's own directory entry
     * already supplies width/height, and the embedded resource has no
     * BITMAPFILEHEADER (the 14-byte `"BM"` + size + offset preamble a
     * standalone `.bmp` file starts with) -- both differences are
     * exactly what this parameter changes vs. the standalone-file path.
     */
    protected void loadBmp(ref ByteReader rdr, int icoHeight = 0, int icoWidth = 0)
    {
        enum biRgb = 0;
        enum biRle8 = 1;
        enum biRle4 = 2;

        w(0);
        h(0);
        d(0);
        ld(0);

        long offbits = 0;
        if (icoHeight < 1)
        {
            ubyte b0 = rdr.readByte();
            ubyte b1 = rdr.readByte();
            if (b0 != 'B' || b1 != 'M')
            {
                ld(errFormat);
                return;
            }
            rdr.readDword(); // file size, unused
            rdr.readWord();
            rdr.readWord(); // reserved
            offbits = rdr.readDword();
        }

        int infoSize = cast(int) rdr.readDword();
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        bool haveMask = false;
        int rowOrder = -1;
        bool use565 = false;
        int width, height, depth, compression, colorsUsed, repcount;
        int bDepth = 3;       // bytes per pixel in the decoded image
        bool useV3Alpha = false; // V3+ header with an alpha mask overrides BI_RGB

        if (infoSize < 40)
        {
            // Old Windows/OS2 BMP header.
            width = rdr.readWord();
            height = rdr.readWord();
            rdr.readWord(); // planes
            depth = rdr.readWord();
            compression = biRgb;
            colorsUsed = 0;
            repcount = infoSize - 12;
        }
        else
        {
            if (icoHeight > 0 && icoWidth > 0)
            {
                rdr.readLong();
                rdr.readLong();
                width = icoWidth;
                height = icoHeight;
            }
            else
            {
                width = rdr.readLong();
                w(width);
                int temp = rdr.readLong();
                if (temp < 0) rowOrder = 1;
                height = temp < 0 ? -temp : temp;
            }

            rdr.readWord(); // planes
            depth = rdr.readWord();
            compression = cast(int) rdr.readDword();
            int dataSize = cast(int) rdr.readDword();
            rdr.readLong();
            rdr.readLong(); // hres, vres
            colorsUsed = cast(int) rdr.readDword();
            rdr.readDword(); // colors_important

            repcount = infoSize - 40;

            if (infoSize >= 56) // BITMAPV3INFOHEADER or later
            {
                rdr.readDword(); // red mask
                rdr.readDword(); // green mask
                rdr.readDword(); // blue mask
                uint alphaMask = rdr.readDword();
                useV3Alpha = compression == biRgb && alphaMask != 0;
                repcount -= 16;
            }

            if (compression == 0 && depth >= 8 && depth != 0 && width > 32 / depth)
            {
                int bpp = depth / 8;
                int maskSize = (((width * bpp + 3) & ~3) * height)
                    + (((((width + 7) / 8) + 3) & ~3) * height);
                if (maskSize == 2 * dataSize)
                {
                    haveMask = true;
                    height = height / 2;
                    bDepth = 4;
                }
            }
        }
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        if (repcount > 0) rdr.skip(repcount);
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        if (width == 0 || height == 0 || depth == 0)
        {
            ld(errFormat);
            return;
        }

        if (colorsUsed == 0 && depth <= 8) colorsUsed = 1 << depth;

        ubyte[3][256] colormap;
        for (int i = 0; i < colorsUsed && i < 256; i++)
        {
            colormap[i][0] = rdr.readByte();
            colormap[i][1] = rdr.readByte();
            colormap[i][2] = rdr.readByte();
            if (infoSize > 12) rdr.readByte(); // pad byte, new-style header only
        }
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        if (depth == 16) use565 = (rdr.readDword() == 0xf800);
        // 32-bit BI_RGB is RGB0 (3 channels) unless a V3+ header gives an
        // alpha mask; BI_BITFIELDS carries alpha. A bitmap inside an .ico
        // is the exception: Windows stores icon alpha in plain BI_RGB data,
        // so it always keeps its 4th channel.
        bool skipPad32 = false;
        if (depth == 32 && !haveMask)
        {
            bool inIco = icoHeight > 0 && icoWidth > 0;
            if (compression == biRgb && !useV3Alpha && !inIco) skipPad32 = true;
            else bDepth = 4;
        }

        if (offbits) rdr.seek(cast(size_t) offbits);
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        if (width < 0 || height < 0)
        {
            ld(errFormat);
            return;
        }
        auto arr = new ubyte[width * height * bDepth];

        int color = 0, rl = 0, align_ = 0, temp = 0;
        ubyte byteVal = 0;

        int startY, endY;
        if (rowOrder < 0)
        {
            startY = height - 1;
            endY = -1;
        }
        else
        {
            startY = 0;
            endY = height;
        }

        for (int y = startY; y != endY; y += rowOrder)
        {
            size_t rowStart = cast(size_t) y * width * bDepth;
            size_t p = rowStart;

            switch (depth)
            {
            case 1: // Bitmap
                {
                    ubyte bit = 128;
                    for (int x = width; x > 0; x--)
                    {
                        if (bit == 128) byteVal = rdr.readByte();
                        int ci = (byteVal & bit) ? 1 : 0;
                        arr[p++] = colormap[ci][2];
                        arr[p++] = colormap[ci][1];
                        arr[p++] = colormap[ci][0];
                        bit = bit > 1 ? cast(ubyte)(bit >> 1) : cast(ubyte) 128;
                    }
                    for (temp = (width + 7) / 8; temp & 3; temp++) rdr.readByte();
                }
                break;

            case 4: // 16-color, plain or RLE4
                {
                    ubyte bit = 0xf0;
                    for (int x = width; x > 0; x--)
                    {
                        if (rl == 0)
                        {
                            if (compression != biRle4)
                            {
                                rl = 2;
                                color = -1;
                            }
                            else
                            {
                                while (align_ > 0)
                                {
                                    align_--;
                                    rdr.readByte();
                                }
                                rl = rdr.readByte();
                                if (rl == 0)
                                {
                                    rl = rdr.readByte();
                                    if (rl == 0) { x++; continue; } // end of line
                                    else if (rl == 1) break; // end of image
                                    else if (rl == 2)
                                    {
                                        rl = rdr.readByte() * rdr.readByte() * width;
                                        color = 0;
                                    }
                                    else
                                    {
                                        color = -1;
                                        align_ = ((4 - (rl & 3)) / 2) & 1;
                                    }
                                }
                                else
                                {
                                    color = rdr.readByte();
                                }
                            }
                        }

                        rl--;

                        if (bit == 0xf0)
                        {
                            temp = color < 0 ? rdr.readByte() : color;
                            int ci = (temp >> 4) & 15;
                            arr[p++] = colormap[ci][2];
                            arr[p++] = colormap[ci][1];
                            arr[p++] = colormap[ci][0];
                            bit = 0x0f;
                        }
                        else
                        {
                            bit = 0xf0;
                            int ci = temp & 15;
                            arr[p++] = colormap[ci][2];
                            arr[p++] = colormap[ci][1];
                            arr[p++] = colormap[ci][0];
                        }
                    }
                    if (rdr.error)
                    {
                        ld(errFormat);
                        return;
                    }
                    if (!compression)
                        for (temp = (width + 1) / 2; temp & 3; temp++) rdr.readByte();
                }
                break;

            case 8: // 256-color, plain or RLE8
                for (int x = width; x > 0; x--)
                {
                    if (compression != biRle8)
                    {
                        rl = 1;
                        color = -1;
                    }

                    if (rl == 0)
                    {
                        while (align_ > 0)
                        {
                            align_--;
                            rdr.readByte();
                        }
                        if (rdr.error)
                        {
                            ld(errFormat);
                            return;
                        }
                        rl = rdr.readByte();
                        if (rl == 0)
                        {
                            rl = rdr.readByte();
                            if (rl == 0) { x++; continue; }
                            else if (rl == 1) break;
                            else if (rl == 2)
                            {
                                rl = rdr.readByte() * rdr.readByte() * width;
                                color = 0;
                            }
                            else
                            {
                                color = -1;
                                align_ = (2 - (rl & 1)) & 1;
                            }
                        }
                        else
                        {
                            color = rdr.readByte();
                        }
                    }
                    if (rdr.error)
                    {
                        ld(errFormat);
                        return;
                    }

                    temp = color < 0 ? rdr.readByte() : color;
                    rl--;

                    arr[p++] = colormap[temp][2];
                    arr[p++] = colormap[temp][1];
                    arr[p++] = colormap[temp][0];
                    if (haveMask) p++;
                }
                if (!compression)
                    for (temp = width; temp & 3; temp++) rdr.readByte();
                break;

            case 16: // 5:5:5 or 5:6:5 packed RGB
                for (int x = width; x > 0; x--, p += bDepth)
                {
                    ubyte b = rdr.readByte(), a = rdr.readByte();
                    if (use565)
                    {
                        arr[p + 2] = cast(ubyte)((b << 3) & 0xf8);
                        arr[p + 1] = cast(ubyte)(((a << 5) & 0xe0) | ((b >> 3) & 0x1c));
                        arr[p + 0] = cast(ubyte)(a & 0xf8);
                    }
                    else
                    {
                        arr[p + 2] = cast(ubyte)((b << 3) & 0xf8);
                        arr[p + 1] = cast(ubyte)(((a << 6) & 0xc0) | ((b >> 2) & 0x38));
                        arr[p + 0] = cast(ubyte)((a << 1) & 0xf8);
                    }
                }
                for (temp = width * 2; temp & 3; temp++) rdr.readByte();
                break;

            case 24: // 24-bit RGB
                for (int x = width; x > 0; x--, p += bDepth)
                {
                    arr[p + 2] = rdr.readByte();
                    arr[p + 1] = rdr.readByte();
                    arr[p + 0] = rdr.readByte();
                }
                for (temp = width * 3; temp & 3; temp++) rdr.readByte();
                break;

            case 32: // 32-bit RGBA
                for (int x = width; x > 0; x--, p += bDepth)
                {
                    arr[p + 2] = rdr.readByte();
                    arr[p + 1] = rdr.readByte();
                    arr[p + 0] = rdr.readByte();
                    ubyte a = rdr.readByte();
                    if (!skipPad32) arr[p + 3] = a;
                }
                break;

            default:
                break;
            }

            if (rdr.error)
            {
                ld(errFormat);
                return;
            }
        }

        if (haveMask)
        {
            for (int y = height - 1; y >= 0; y--)
            {
                size_t p = cast(size_t) y * width * bDepth + 3;
                ubyte bit = 128;
                for (int x = width; x > 0; x--, p += bDepth)
                {
                    if (bit == 128) byteVal = rdr.readByte();
                    arr[p] = (byteVal & bit) ? 0 : 255;
                    bit = bit > 1 ? cast(ubyte)(bit >> 1) : cast(ubyte) 128;
                }
                for (temp = (width + 7) / 8; temp & 3; temp++) rdr.readByte();
            }
        }

        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        array = arr;
        w(width);
        h(height);
        d(bDepth);
        ld(0);
        hasData(true);
    }
}

/**
 * Encodes a packed, top-down RGB pixel buffer (`w*h*3` bytes, one byte
 * per red/green/blue channel per pixel, row 0 = top of image -- the
 * same layout `fl.draw.readPixelsFromDrawable()`/`RGBImage.array`
 * already use) as an uncompressed 24-bit-per-pixel BMP file, in
 * memory. Ported from `Fl_Unix_System_Driver::create_bmp()`
 * (`src/drivers/Unix/Fl_Unix_System_Driver.cxx`) -- the write-side
 * counterpart to this module's own decoder above (`BMPImage`, which
 * can decode this function's own output straight back via its
 * in-memory-bytes constructor, `new BMPImage(name, createBmp(...))`).
 *
 * The one real caller: `fl.core.copyImage()` (backing
 * `fl.widget_surface.CopySurface`'s image-to-clipboard support,
 * `test/device.cxx`'s "Fl_Copy_Surface" demo), which owns the X11
 * selection with this function's raw output, offered to other
 * applications as target `image/bmp` -- matching FLTK's own
 * `Fl_X11_Screen_Driver::copy_image()` exactly.
 *
 * Returns an empty array for a degenerate (`w <= 0`/`h <= 0`) or too-
 * short `rgbData` input.
 */
package(fl) ubyte[] createBmp(const(ubyte)[] rgbData, int w, int h)
{
    if (w <= 0 || h <= 0 || rgbData.length < cast(size_t) w * h * 3) return null;

    int rowBytes = ((3 * w + 3) / 4) * 4; // rounded up to a multiple of 4
    int pixelDataSize = h * rowBytes;
    int fileSize = 14 + 40 + pixelDataSize;

    auto bmp = new ubyte[fileSize];
    size_t pos = 0;

    void putByte(ubyte b) { bmp[pos++] = b; }
    void putWord(ushort v) { putByte(v & 0xFF); putByte((v >> 8) & 0xFF); }
    void putDword(int v)
    {
        putByte(v & 0xFF);
        putByte((v >> 8) & 0xFF);
        putByte((v >> 16) & 0xFF);
        putByte((v >> 24) & 0xFF);
    }

    // BITMAPFILEHEADER
    putByte('B'); putByte('M');
    putDword(fileSize);
    putDword(0);
    putDword(14 + 40);

    // BITMAPINFOHEADER
    putDword(40);
    putDword(w);
    putDword(h);
    putWord(1);
    putWord(24); // bits per pixel
    putDword(0); // BI_RGB, uncompressed
    putDword(pixelDataSize);
    putDword(0); // horizontal resolution
    putDword(0); // vertical resolution
    putDword(0); // colors used (0 -> 1 << bits_per_pixel)
    putDword(0); // important colors

    // Pixel data, bottom-up (file row 0 = bottom image row), each
    // pixel BGR.
    for (int y = 0; y < h; y++)
    {
        int srcRow = h - 1 - y;
        const(ubyte)* src = rgbData.ptr + cast(size_t) srcRow * w * 3;
        size_t rowStart = pos;
        for (int x = 0; x < w; x++)
        {
            putByte(src[x * 3 + 2]);
            putByte(src[x * 3 + 1]);
            putByte(src[x * 3 + 0]);
        }
        pos = rowStart + rowBytes; // skip any row-padding bytes (already 0)
    }

    return bmp;
}

unittest
{
    import fl.enumerations : black;

    // 24-bit uncompressed BMP, 2x2, bottom-up row order (the common
    // case): red, green / blue, yellow (top row first in the file is
    // the *bottom* image row, matching BMP's own default orientation).
    ubyte[] bmp;
    void putWord(ushort v) { bmp ~= [cast(ubyte)(v), cast(ubyte)(v >> 8)]; }
    void putDword(uint v)
    {
        bmp ~= [cast(ubyte) v, cast(ubyte)(v >> 8), cast(ubyte)(v >> 16), cast(ubyte)(v >> 24)];
    }

    // BITMAPFILEHEADER
    bmp ~= ['B', 'M'];
    putDword(0); // file size, unused by the reader
    putWord(0);
    putWord(0); // reserved
    putDword(54); // offbits: 14 (file header) + 40 (info header)

    // BITMAPINFOHEADER
    putDword(40); // info_size
    putDword(2); // width
    putDword(2); // height (positive: bottom-up)
    putWord(1); // planes
    putWord(24); // depth
    putDword(0); // BI_RGB
    putDword(0); // dataSize
    putDword(0);
    putDword(0); // hres/vres
    putDword(0); // colors_used
    putDword(0); // colors_important

    // Pixel data, bottom-up: row 0 (file) = bottom image row = blue,yellow;
    // row 1 (file) = top image row = red,green. Each pixel BGR (2*3=6
    // bytes/row, not a multiple of 4, so each row needs 2 padding bytes).
    bmp ~= [255, 0, 0, 0, 255, 255]; // blue, yellow (BGR order)
    bmp ~= [0, 0]; // row padding to 4-byte boundary
    bmp ~= [0, 0, 255, 0, 255, 0]; // red, green (BGR order)
    bmp ~= [0, 0]; // row padding

    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import fl.bmp_image : BMPImage;

    auto path = buildPath(tempDir(), "fldtk-bmp-test-" ~ randomUUID().toString() ~ ".bmp");
    scope (exit) if (exists(path)) remove(path);
    write(path, bmp);

    auto img = new BMPImage(path);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 2 && img.d() == 3);
    // Row 0 (top of image) = red, green; row 1 (bottom) = blue, yellow.
    assert(img.array[0 .. 6] == [255, 0, 0, 0, 255, 0]);
    assert(img.array[6 .. 12] == [0, 0, 255, 255, 255, 0]);
}

unittest
{
    // In-memory constructor + a malformed (missing "BM" signature)
    // buffer reports errFormat.
    auto bad = new BMPImage("bad", [0, 1, 2, 3]);
    assert(bad.fail() == Image.errFormat);
}

unittest
{
    auto missing = new BMPImage("/nonexistent/path/does-not-exist.bmp");
    assert(missing.fail() == Image.errFileAccess);
}

unittest
{
    // createBmp() round-trips through BMPImage's own decoder: encode a
    // 2x2 top-down RGB buffer, decode it back, and confirm every pixel
    // survived (including the BGR-vs-RGB byte-order flip both
    // directions apply).
    ubyte[] rgb = [
        255, 0, 0,    0, 255, 0,   // top row: red, green
        0, 0, 255,    255, 255, 0, // bottom row: blue, yellow
    ];
    auto bmp = createBmp(rgb, 2, 2);
    assert(bmp.length > 0);

    auto img = new BMPImage("roundtrip", bmp);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 2 && img.d() == 3);
    assert(img.array[0 .. 6] == [255, 0, 0, 0, 255, 0]);
    assert(img.array[6 .. 12] == [0, 0, 255, 255, 255, 0]);
}

unittest
{
    // Degenerate inputs return an empty array rather than crashing.
    assert(createBmp(null, 0, 0).length == 0);
    assert(createBmp([1, 2, 3], -1, 5).length == 0);
    assert(createBmp([1, 2, 3], 5, 5).length == 0); // too short for 5x5x3
}
