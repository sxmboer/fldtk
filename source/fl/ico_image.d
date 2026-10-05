/*
 * Ported from FL/Fl_ICO_Image.H + src/Fl_ICO_Image.cxx (FLTK 1.5.0): Fl_ICO_Image, a Windows Icon (.ico) file
 * reader. Genuinely subclasses Fl_BMP_Image FLTK -- an .ico file
 * is a small directory of embedded image resources, each either a
 * BMP-format bitmap with no outer BITMAPFILEHEADER (handled by
 * calling straight into fl.bmp_image.BMPImage's own protected
 * loadBmp(), passing the directory entry's width/height in place of
 * the missing file-header/BITMAPINFOHEADER dimensions -- see that
 * module's own top comment) or a full embedded PNG file.
 *
 * PNG-embedded icon resources (detected via the standard 8-byte PNG
 * magic number) decode by delegating to `fl.png_image.PngImage`'s
 * existing in-memory-buffer constructor --
 * FLTK's own `rdr.is_data()` branch (`src/Fl_ICO_Image.cxx`) does
 * the exact same thing: `new Fl_PNG_Image(rdr.name(),
 * rdr.data_start()+offset, size)`, where `size` deliberately runs to
 * the end of the surrounding .ico buffer ("the PNG may end before
 * that", per that file's own comment) rather than being trimmed to
 * `dwBytesInRes` -- `PngImage`'s own `readPng()` already stops at the
 * first `IEND` chunk and ignores anything after, so handing it
 * `rdr.data[offset .. $]` (this port's equivalent slice) needs no
 * length calculation at all. FLTK's *other* branch -- reopening the
 * source file by name and seeking to `offset` for the file-backed case
 * -- has no equivalent here: `ByteReader` always wraps a fully-read
 * in-memory buffer regardless of whether `ICOImage` was constructed
 * from a filename or raw data (see this class's own two constructors),
 * so every load takes what FLTK treats as the memory-buffer path.
 */
module fl.ico_image;

import fl.image : Image;
import fl.bmp_image : BMPImage, ByteReader;
import fl.png_image : PngImage;

/// One entry of an .ico file's directory -- ported from Fl_ICO_Image's
/// own public IconDirEntry struct. Widths/heights of 0 in the file mean
/// 256 (a byte can't represent 256 directly); already resolved to 256
/// by the time it lands here.
struct IconDirEntry
{
    int bWidth;
    int bHeight;
    int bColorCount;
    int bReserved;
    int wPlanes;
    int wBitCount;
    int dwBytesInRes;
    int dwImageOffset;
}

class ICOImage : BMPImage
{
    private IconDirEntry[] icons_;

    /// Loads the icon at directory index id from filename. id == -1
    /// (the default) auto-picks the highest-resolution entry (ties
    /// broken by the highest color depth); id == -2 parses the
    /// directory only, loading no image at all (idcount()/
    /// icondirentry() still work); id >= 0 loads that specific entry.
    this(string filename, int id = -1)
    {
        super();
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
        loadIco(rdr, id);
    }

    /// Loads an icon from an in-memory buffer (e.g. compiled-in
    /// resource data) instead of a file.
    this(string imagename, const(ubyte)[] data, int id = -1)
    {
        super();
        auto rdr = ByteReader(data, 0, false);
        loadIco(rdr, id);
    }

    /// Number of images listed in the .ico directory.
    int idcount() const { return cast(int) icons_.length; }

    /// The i'th directory entry (0 .. idcount()-1).
    IconDirEntry icondirentry(int i) const { return icons_[i]; }

    private void loadIco(ref ByteReader rdr, int id)
    {
        w(0);
        h(0);
        d(0);
        ld(0);

        ushort reserved = rdr.readWord();
        ushort type = rdr.readWord();
        if (rdr.error || reserved != 0 || type != 1)
        {
            ld(errFormat);
            return;
        }

        int count = rdr.readWord();
        if (rdr.error || count <= 0)
        {
            ld(errFormat);
            return;
        }

        icons_.length = count;
        foreach (i; 0 .. count)
        {
            int bw = rdr.readByte();
            int bh = rdr.readByte();
            icons_[i].bWidth = bw == 0 ? 256 : bw;
            icons_[i].bHeight = bh == 0 ? 256 : bh;
            icons_[i].bColorCount = rdr.readByte();
            icons_[i].bReserved = rdr.readByte();
            icons_[i].wPlanes = rdr.readWord();
            icons_[i].wBitCount = rdr.readWord();
            icons_[i].dwBytesInRes = cast(int) rdr.readDword();
            icons_[i].dwImageOffset = cast(int) rdr.readDword();
        }
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        if (id <= -2) return; // directory-only load

        int pick = id;
        if (id == -1)
        {
            pick = 0;
            foreach (i; 1 .. count)
            {
                long bestArea = cast(long) icons_[pick].bWidth * icons_[pick].bHeight;
                long area = cast(long) icons_[i].bWidth * icons_[i].bHeight;
                if (area > bestArea
                    || (area == bestArea && icons_[i].wBitCount > icons_[pick].wBitCount))
                    pick = i;
            }
        }

        if (pick < 0 || pick >= count)
        {
            ld(errFormat);
            return;
        }

        auto entry = icons_[pick];
        if (entry.bWidth <= 0 || entry.bHeight <= 0 || entry.dwImageOffset <= 0
            || entry.dwBytesInRes <= 0)
        {
            ld(errFormat);
            return;
        }

        rdr.seek(cast(size_t) entry.dwImageOffset);
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        static immutable ubyte[8] pngMagic = [0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A];
        bool isPng = rdr.pos + 8 <= rdr.data.length && rdr.data[rdr.pos .. rdr.pos + 8] == pngMagic;

        if (isPng)
        {
            auto png = new PngImage("ico-embedded-png", rdr.data[rdr.pos .. $]);
            if (png.fail())
            {
                ld(errFormat);
                return;
            }
            w(png.w());
            h(png.h());
            d(png.d());
            array = png.array;
            hasData(true);
            return;
        }

        w(entry.bWidth);
        h(entry.bHeight);
        d(4);
        rdr.seek(cast(size_t) entry.dwImageOffset);
        loadBmp(rdr, entry.bHeight, entry.bWidth);
    }
}

unittest
{
    // A minimal 1-entry .ico wrapping a 2x2, 32-bit uncompressed BMP
    // resource (no outer "BM"/BITMAPFILEHEADER -- the resource starts
    // straight at its BITMAPINFOHEADER, matching real .ico files).
    ubyte[] ico;
    void putWordLE(ushort v) { ico ~= [cast(ubyte)(v), cast(ubyte)(v >> 8)]; }
    void putDwordLE(uint v)
    {
        ico ~= [cast(ubyte) v, cast(ubyte)(v >> 8), cast(ubyte)(v >> 16), cast(ubyte)(v >> 24)];
    }

    // ICONDIR
    putWordLE(0); // reserved
    putWordLE(1); // type = icon
    putWordLE(1); // count

    // ICONDIRENTRY
    ico ~= [2, 2]; // width, height
    ico ~= [0, 0]; // color count, reserved
    putWordLE(1); // planes
    putWordLE(32); // bit count
    // Resource: BITMAPINFOHEADER (40) + pixel data (2 rows * 8 bytes, no padding at depth 32) = 56
    putDwordLE(56); // dwBytesInRes
    putDwordLE(22); // dwImageOffset: 6 (ICONDIR) + 16 (ICONDIRENTRY) = 22

    assert(ico.length == 22);

    // Embedded BMP resource, no file header. depth 32 always forces
    // bDepth=4 (real alpha channel) regardless of the havemask
    // heuristic, unlike the plain fl.bmp_image unittest's 24-bit case.
    putDwordLE(40); // info_size
    putDwordLE(2); // width (ignored -- loadBmp() uses ico_width/ico_height)
    putDwordLE(2); // height (ignored)
    putWordLE(1); // planes
    putWordLE(32); // depth
    putDwordLE(0); // BI_RGB
    putDwordLE(0); // dataSize
    putDwordLE(0);
    putDwordLE(0); // hres/vres
    putDwordLE(0); // colors_used
    putDwordLE(0); // colors_important

    // Pixel data (BGRA per pixel, no row padding at depth 32),
    // bottom-up: row0(file)=bottom=blue,yellow; row1(file)=top=red,green.
    ico ~= [255, 0, 0, 255, 0, 255, 255, 255]; // blue, yellow (BGRA)
    ico ~= [0, 0, 255, 255, 0, 255, 0, 255]; // red, green (BGRA)

    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-ico-test-" ~ randomUUID().toString() ~ ".ico");
    scope (exit) if (exists(path)) remove(path);
    write(path, ico);

    auto img = new ICOImage(path);
    assert(!img.fail());
    assert(img.idcount() == 1);
    auto entry = img.icondirentry(0);
    assert(entry.bWidth == 2 && entry.bHeight == 2);
    assert(img.w() == 2 && img.h() == 2 && img.d() == 4);
    // Row 0 (top) = red, green; row 1 (bottom) = blue, yellow; alpha 255 (no mask).
    assert(img.array[0 .. 4] == [255, 0, 0, 255]);
    assert(img.array[4 .. 8] == [0, 255, 0, 255]);
    assert(img.array[8 .. 12] == [0, 0, 255, 255]);
    assert(img.array[12 .. 16] == [255, 255, 0, 255]);
}

unittest
{
    // A minimal 1-entry .ico wrapping a full embedded PNG resource
    // (no BMP header at all -- the resource starts straight at the
    // PNG's own 8-byte signature, matching a real modern .ico file).
    import fl.png_image : writePng;
    import std.file : write, remove, read, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto pngPath = buildPath(tempDir(), "fldtk-ico-png-src-" ~ randomUUID().toString() ~ ".png");
    scope (exit) if (exists(pngPath)) remove(pngPath);
    // 2x2 RGB: red, green / blue, yellow.
    ubyte[] pixels = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    assert(writePng(pngPath, pixels, 2, 2, 3) == 0);
    ubyte[] pngBytes = cast(ubyte[]) read(pngPath);

    ubyte[] ico;
    void putWordLE(ushort v) { ico ~= [cast(ubyte)(v), cast(ubyte)(v >> 8)]; }
    void putDwordLE(uint v)
    {
        ico ~= [cast(ubyte) v, cast(ubyte)(v >> 8), cast(ubyte)(v >> 16), cast(ubyte)(v >> 24)];
    }

    putWordLE(0); // reserved
    putWordLE(1); // type = icon
    putWordLE(1); // count
    ico ~= [2, 2, 0, 0]; // width, height, color count, reserved
    putWordLE(1); // planes
    putWordLE(24); // bit count
    putDwordLE(cast(uint) pngBytes.length); // dwBytesInRes
    putDwordLE(22); // dwImageOffset: 6 (ICONDIR) + 16 (ICONDIRENTRY)
    assert(ico.length == 22);
    ico ~= pngBytes;

    auto img = new ICOImage("in-memory", ico);
    assert(!img.fail());
    assert(img.idcount() == 1);
    assert(img.w() == 2 && img.h() == 2 && img.d() == 3);
    assert(img.array[0 .. 3] == [255, 0, 0]); // red
    assert(img.array[3 .. 6] == [0, 255, 0]); // green
    assert(img.array[6 .. 9] == [0, 0, 255]); // blue
    assert(img.array[9 .. 12] == [255, 255, 0]); // yellow
}

unittest
{
    // Directory-only load (id == -2): no image, but idcount()/
    // icondirentry() still work.
    ubyte[] ico;
    void putWordLE(ushort v) { ico ~= [cast(ubyte)(v), cast(ubyte)(v >> 8)]; }
    void putDwordLE(uint v)
    {
        ico ~= [cast(ubyte) v, cast(ubyte)(v >> 8), cast(ubyte)(v >> 16), cast(ubyte)(v >> 24)];
    }

    putWordLE(0);
    putWordLE(1);
    putWordLE(1);
    ico ~= [16, 16, 0, 0];
    putWordLE(1);
    putWordLE(32);
    putDwordLE(1000);
    putDwordLE(22);

    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto path = buildPath(tempDir(), "fldtk-ico-test-" ~ randomUUID().toString() ~ ".ico");
    scope (exit) if (exists(path)) remove(path);
    write(path, ico);

    auto img = new ICOImage(path, -2);
    assert(img.idcount() == 1);
    assert(img.icondirentry(0).bWidth == 16);
    assert(img.w() == 0 && img.h() == 0); // no image loaded
}

unittest
{
    // Malformed directory (wrong "type" word) reports errFormat.
    auto bad = new ICOImage("bad", [0, 0, 2, 0, 1, 0]);
    assert(bad.fail() == Image.errFormat);
}
