/*
 * Ported from FL/Fl_GIF_Image.H + src/Fl_GIF_Image.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk): Fl_GIF_Image, a Compuserve GIF file reader. No
 * external library needed -- GIF's LZW compression is simple enough to
 * decode natively (same shape as fl.bmp_image's own RLE decoder),
 * unlike JPEG/PNG's real entropy coders. (Earlier revisions of this
 * comment listed GIF/AnimGIF under CLAUDE.md's "Deferred: external-
 * library-backed features" -- that was based on a mistaken premise;
 * neither `Fl_GIF_Image.cxx` nor `Fl_Anim_GIF_Image.cxx` links any
 * external codec.)
 *
 * Like FLTK, `GifImage` is a `Pixmap` subclass: the decoded pixel-
 * index rows and color table of the *first* frame are converted into
 * `fl.pixmap.Pixmap`'s "compressed colormap" XPM format (`ncolors < 0`,
 * one table row of packed `(char, r, g, b)` 4-byte entries) via
 * `convertToXpm()`, ported from FLTK's `convert_to_xpm()` -- this
 * reuses `Pixmap`'s already-real `draw()`/`copy()`/`colorAverage()`/
 * `desaturate()` machinery as-is, rather than duplicating it for a
 * second RGBA-based image type. A transparent pixel is real too: GIF's
 * single "transparent color index" is remapped to the ` ` (space)
 * character FLTK's `Pixmap.convertPixmap()` already treats as the
 * transparency marker.
 *
 * `loadGif()` always parses every frame in the file (not just the
 * first), notifying `onFrameData()`/`onExtensionData()` per frame --
 * ported from FLTK's `Fl_GIF_Image::load_gif_(rdr, anim)`, whose
 * `anim` parameter controls this exact thing. `fl.anim_gif_image.
 * AnimGifImage` overrides those two hooks to build real multi-frame
 * animation on top of this same parser, matching FLTK's own
 * `Fl_Anim_GIF_Image : public Fl_GIF_Image` relationship -- no second
 * GIF parser exists anywhere in this port. `anim=false` (the two public
 * constructors below) stops after frame 0, matching FLTK's own
 * `if (!anim) break;`.
 *
 * Ported from a plain in-memory byte buffer rather than FLTK's own
 * dual file-or-memory `Fl_Image_Reader` helper -- reuses
 * `fl.bmp_image.ByteReader` (already `package(fl)`, little-endian,
 * exactly what GIF's `read_word()` needs) instead of introducing a
 * second reader type, matching this port's established convention
 * (see `fl.bmp_image`'s own module comment).
 *
 * Not ported: the version-string ("87a" vs "89a") mismatch warning
 * (FLTK logs it via `Fl::warning()`, a diagnostic with no
 * correctness effect).
 */
module fl.gif_image;

import fl.image : Image;
import fl.pixmap : Pixmap;
import fl.bmp_image : ByteReader;
import std.format : format;

class GifImage : Pixmap
{
    /// Ported from `Fl_GIF_Image::animate` -- switches whether
    /// `fl.shared_image`'s format-sniffing should hand a GIF file to
    /// `fl.anim_gif_image.AnimGifImage` instead of a plain `GifImage`.
    /// (`fl.shared_image` doesn't have GIF format-sniffing wired up yet
    /// -- see that module's own row in PORTING.md -- so this flag is
    /// still inert in practice, just no longer for a decoder-existence
    /// reason.)
    static bool animate = false;

    /// Empty-shell constructor for `fl.anim_gif_image.AnimGifImage`'s
    /// use only -- mirrors FLTK's `protected Fl_GIF_Image()` and
    /// this port's own established `fl.bmp_image.BMPImage`/
    /// `fl.ico_image.ICOImage` precedent for the same shape. Loads
    /// nothing; the subclass calls `load()` itself once its own fields
    /// are initialized (constructing with a vtable already pointed at
    /// the most-derived class -- see CLAUDE.md's note on why loading
    /// from *this* constructor instead would reach an overridden hook
    /// before the subclass's own state exists).
    protected this()
    {
        super(null);
    }

    this(string filename)
    {
        super(null);
        load(filename, false);
    }

    this(string imagename, const(ubyte)[] data)
    {
        super(null);
        load(imagename, data, false);
    }

    /// Ported from the `protected` `Fl_GIF_Image::load(const char*,
    /// bool)` overloads -- used by `AnimGifImage` (`anim=true`) and,
    /// with `anim=false`, by this class's own two public constructors
    /// above.
    protected void load(string filename, bool anim)
    {
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
        loadGif(rdr, anim);
    }

    /// ditto
    protected void load(string imagename, const(ubyte)[] data, bool anim)
    {
        auto rdr = ByteReader(data, 0, false);
        loadGif(rdr, anim);
    }

    /// A single 24-bit color-table entry -- ported from `Fl_GIF_Image::
    /// GIF_FRAME::CPAL`.
    protected struct Cpal
    {
        ubyte r, g, b;
    }

    /// Ported from `Fl_GIF_Image::GIF_FRAME` -- passed to
    /// `onFrameData()`/`onExtensionData()` per block, giving a
    /// subclass (`AnimGifImage`) everything it needs to build a real
    /// animation on top of this class's own single-frame decode.
    protected struct GifFrame
    {
        int ifrm; // 0-based frame index
        int width, height; // GIF screen (canvas) dimensions -- only meaningful when ifrm==0
        int x, y, w, h; // this frame's rectangle within the screen
        int clrs; // color table size
        int bkgd; // background color index
        int trans; // transparent color index, or -1 if this frame has none
        int dispose; // disposal method (0-3, see the GIF89a spec)
        int delay; // FLTK's own encoded form -- userInput ? -delay-1 : delay
        const(ubyte)[] bptr; // decoded pixel bytes (w*h) for an image block; the
        // raw extension payload for an extension block
        const(Cpal)[] cpal; // this frame's color table (never mutated -- see
        // loadGif()'s own note on why a separate copy from
        // the "working" table convertToXpm() mutates exists)
    }

    /// Ported from `Fl_GIF_Image::on_frame_data()` -- a no-op hook here,
    /// overridden by `AnimGifImage` to composite each frame into its
    /// own offscreen animation buffer.
    protected void onFrameData(ref GifFrame f)
    {
    }

    /// Ported from `Fl_GIF_Image::on_extension_data()` -- a no-op hook
    /// here, overridden by `AnimGifImage` to read the Netscape loop-
    /// count Application Extension.
    protected void onExtensionData(ref GifFrame f)
    {
    }

    /*
     * Ported from `Fl_GIF_Image::load_gif_()`: parses the header,
     * global color table, and every block (Graphic Control/
     * Application/Comment/Plain-Text extensions, Image Descriptors) up
     * to the Trailer, notifying `onFrameData()`/`onExtensionData()` per
     * block. `anim=false` stops after the first Image Descriptor,
     * matching FLTK's own `if (!anim) break;`.
     *
     * Keeps two separate representations of the color table, matching
     * FLTK exactly: `cmapR`/`cmapG`/`cmapB` (FLTK's `CMap`) is
     * a *working* copy that gets mutated by the "no color table"/
     * "transparent pixel outside color table" workarounds below, and
     * is what `convertToXpm()` consumes for frame 0's `Pixmap` data;
     * `globalTable`/`localTable` are untouched copies of exactly what
     * was read from the file, handed to `onFrameData()`'s `cpal` field
     * unmodified. Handing a subclass the *working* copy instead would
     * be a real bug for `AnimGifImage`: a mutated size or set of
     * defaulted colors that only makes sense for the first-frame XPM
     * conversion has no business leaking into how every frame's own
     * pixels get colored.
     */
    private void loadGif(ref ByteReader rdr, bool anim)
    {
        ubyte[6] sig;
        foreach (i; 0 .. 6) sig[i] = rdr.readByte();
        if (rdr.error || sig[0] != 'G' || sig[1] != 'I' || sig[2] != 'F')
        {
            ld(errFormat);
            return;
        }

        int screenWidth = rdr.readWord();
        int screenHeight = rdr.readWord();

        ubyte ch = rdr.readByte();
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }
        bool hasColormap = (ch & 0x80) != 0;
        int colorMapSize = hasColormap ? 2 << (ch & 7) : 0;

        int backgroundColorIndex = rdr.readByte();
        rdr.readByte(); // aspect ratio
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        ubyte[256] cmapR, cmapG, cmapB; // the "working" CMap -- see doc comment above
        Cpal[256] globalTable;
        bool hasGlobalTable = hasColormap;
        if (hasColormap)
        {
            foreach (i; 0 .. colorMapSize)
            {
                cmapR[i] = rdr.readByte();
                cmapG[i] = rdr.readByte();
                cmapB[i] = rdr.readByte();
                globalTable[i] = Cpal(cmapR[i], cmapG[i], cmapB[i]);
            }
        }
        if (rdr.error)
        {
            ld(errFormat);
            return;
        }

        bool hasTransparent = false;
        bool userInput = false;
        int transparentPixel = 0;
        int delay = 0;
        int dispose = 0;
        Cpal[256] localTable;

        int frame = 0;

        for (;;)
        {
            int i = rdr.readByte();
            if (rdr.error)
            {
                ld(errFormat);
                return;
            }
            int blocklen = 0;

            if (i == 0x21) // extension
            {
                ubyte extType = rdr.readByte();
                blocklen = rdr.readByte();
                if (rdr.error)
                {
                    ld(errFormat);
                    return;
                }

                if (extType == 0xF9 && blocklen == 4) // Graphic Control Extension
                {
                    ubyte bits = rdr.readByte();
                    dispose = (bits >> 2) & 7;
                    delay = rdr.readWord();
                    transparentPixel = rdr.readByte();
                    blocklen = rdr.readByte(); // block terminator, must be 0
                    if (rdr.error)
                    {
                        ld(errFormat);
                        return;
                    }
                    hasTransparent = (bits & 1) != 0;
                    userInput = (bits & 2) != 0;
                }
                else if (extType == 0xFF) // Application Extension
                {
                    ubyte[512] buf;
                    int bufLen = 0;
                    foreach (k; 0 .. blocklen)
                    {
                        if (bufLen < buf.length) buf[bufLen] = rdr.readByte();
                        else rdr.readByte();
                        bufLen++;
                    }
                    blocklen = rdr.readByte(); // next sub-block too, for NETSCAPE ext.
                    if (rdr.error)
                    {
                        ld(errFormat);
                        return;
                    }
                    if (blocklen)
                    {
                        foreach (k; 0 .. blocklen)
                        {
                            if (bufLen < buf.length) buf[bufLen] = rdr.readByte();
                            else rdr.readByte();
                            bufLen++;
                        }
                        blocklen = rdr.readByte();
                        if (rdr.error)
                        {
                            ld(errFormat);
                            return;
                        }
                    }

                    auto f = GifFrame(frame);
                    f.bptr = buf[0 .. bufLen > buf.length ? buf.length : bufLen];
                    onExtensionData(f);
                }
                // Comment (0xFE)/Plain-Text (0x01)/unknown extensions:
                // nothing more to do -- their sub-blocks are still
                // correctly skipped below.
            }
            else if (i == 0x2c) // Image Descriptor
            {
                int left = rdr.readWord();
                int top = rdr.readWord();
                int width = rdr.readWord();
                int height = rdr.readWord();
                ch = rdr.readByte();
                if (rdr.error)
                {
                    ld(errFormat);
                    return;
                }
                bool interlace = (ch & 0x40) != 0;
                bool hasLocalTable = (ch & 0x80) != 0;
                if (hasLocalTable) // local color table
                {
                    colorMapSize = 2 << (ch & 7);
                    foreach (i2; 0 .. colorMapSize)
                    {
                        cmapR[i2] = rdr.readByte();
                        cmapG[i2] = rdr.readByte();
                        cmapB[i2] = rdr.readByte();
                        localTable[i2] = Cpal(cmapR[i2], cmapG[i2], cmapB[i2]);
                    }
                }
                if (rdr.error)
                {
                    ld(errFormat);
                    return;
                }

                int codeSize = rdr.readByte();
                if (rdr.error)
                {
                    ld(errFormat);
                    return;
                }
                codeSize++;

                // No color table at all: the standard allows this and
                // recommends a default black/white(/ramp) table.
                if (colorMapSize == 0)
                {
                    int bpp = codeSize - 1;
                    colorMapSize = 1 << bpp;
                    cmapR[0] = cmapG[0] = cmapB[0] = 0;
                    cmapR[1] = cmapG[1] = cmapB[1] = 255;
                    foreach (k; 2 .. colorMapSize)
                        cmapR[k] = cmapG[k] = cmapB[k] = cast(ubyte)(255 * k / (colorMapSize - 1));
                }

                // Workaround for broken GIF files (matches FLTK).
                int bitsPerPixel = codeSize - 1;
                if ((1 << bitsPerPixel) <= 256) colorMapSize = 1 << bitsPerPixel;

                // Transparent index outside the color map: extend it.
                if (hasTransparent && transparentPixel >= colorMapSize)
                {
                    foreach (k; colorMapSize .. transparentPixel + 1)
                        cmapR[k] = cmapG[k] = cmapB[k] = 0xff;
                    colorMapSize = transparentPixel + 1;
                }

                if (width <= 0 || height <= 0)
                {
                    ld(errFormat);
                    return;
                }

                auto image = new ubyte[width * height];
                if (!lzwDecode(rdr, image, width, height, codeSize, colorMapSize, interlace))
                {
                    ld(errFormat);
                    return;
                }

                auto gf = GifFrame(frame);
                gf.width = screenWidth;
                gf.height = screenHeight;
                gf.x = left;
                gf.y = top;
                gf.w = width;
                gf.h = height;
                gf.clrs = colorMapSize;
                gf.bkgd = backgroundColorIndex;
                gf.trans = hasTransparent ? transparentPixel : -1;
                gf.dispose = dispose;
                gf.delay = userInput ? -delay - 1 : delay;
                gf.bptr = image;
                Cpal[256] synthCpal;
                if (hasLocalTable)
                    gf.cpal = localTable[0 .. colorMapSize];
                else if (hasGlobalTable)
                    gf.cpal = globalTable[0 .. colorMapSize];
                else
                {
                    foreach (k; 0 .. colorMapSize)
                        synthCpal[k] = Cpal(cmapR[k], cmapG[k], cmapB[k]);
                    gf.cpal = synthCpal[0 .. colorMapSize];
                }
                onFrameData(gf);

                // Convert the first frame to XPM data (frame 0's own
                // real purpose: static-decode fallback / Fl_Pixmap-
                // compatible presentation). `image` is mutated in
                // place by convertToXpm() -- safe, since onFrameData()
                // above has already consumed it synchronously.
                if (frame == 0)
                {
                    xpmData = convertToXpm(image, width, height, cmapR, cmapG, cmapB,
                        colorMapSize, gf.trans);
                    w(width);
                    h(height);
                    ld(0);
                }

                if (!anim) return; // matches FLTK's `if (!anim) break;`
                frame++;
            }
            else if (i == 0x3b) // Trailer -- end of GIF data
            {
                if (frame == 0) ld(errNoImage); // no image was ever found
                return;
            }
            else
            {
                ld(errFormat); // unrecognized block
                return;
            }

            if (rdr.error)
            {
                ld(errFormat);
                return;
            }
            while (blocklen > 0)
            {
                rdr.skip(blocklen);
                blocklen = rdr.readByte();
                if (rdr.error)
                {
                    ld(errFormat);
                    return;
                }
            }
        }
    }
}

/*
 * Ported from `Fl_GIF_Image::lzw_decode()` -- the GIF/TIFF-style LZW
 * decompressor (variable code width 3-12 bits, packed LSB-first across
 * byte boundaries with the format's own annoying per-block length
 * bytes interspersed in the stream). Returns `false` only on a hard
 * read error (propagated by the caller as `errFormat`); a corrupt code
 * mid-stream matches FLTK's own leniency -- stops decoding and
 * keeps whatever was already written rather than failing the image.
 */
private bool lzwDecode(ref ByteReader rdr, ubyte[] image, int width, int height,
    int codeSize, int colorMapSize, bool interlace)
{
    int yc = 0, pass = 0; // de-interlacing state
    size_t p = 0;
    size_t eol = width;

    int initCodeSize = codeSize;
    int clearCode = 1 << (codeSize - 1);
    int eofCode = clearCode + 1;
    int firstFree = clearCode + 2;
    int finChar = 0;
    int readMask = (1 << codeSize) - 1;
    int freeCode = firstFree;
    int oldCode = clearCode;

    short[4096] prefix;
    ubyte[4096] suffix;

    int blocklen = rdr.readByte();
    int thisByte = rdr.readByte();
    blocklen--;
    if (rdr.error) return false;
    int frombit = 0;

    for (;;)
    {
        int curCode = thisByte;
        if (frombit + codeSize > 7)
        {
            if (blocklen <= 0)
            {
                blocklen = rdr.readByte();
                if (rdr.error) return false;
                if (blocklen <= 0) break;
            }
            thisByte = rdr.readByte();
            blocklen--;
            if (rdr.error) return false;
            curCode |= thisByte << 8;
        }
        if (frombit + codeSize > 15)
        {
            if (blocklen <= 0)
            {
                blocklen = rdr.readByte();
                if (rdr.error) return false;
                if (blocklen <= 0) break;
            }
            thisByte = rdr.readByte();
            blocklen--;
            if (rdr.error) return false;
            curCode |= thisByte << 16;
        }
        curCode = (curCode >> frombit) & readMask;
        frombit = (frombit + codeSize) % 8;

        if (curCode == clearCode)
        {
            codeSize = initCodeSize;
            readMask = (1 << codeSize) - 1;
            freeCode = firstFree;
            oldCode = clearCode;
            continue;
        }

        if (curCode == eofCode)
        {
            rdr.skip(blocklen);
            rdr.readByte(); // block terminator, must follow
            break;
        }

        ubyte[4097] outCode;
        size_t tp = 0;
        int i;
        if (curCode < freeCode)
            i = curCode;
        else if (curCode == freeCode)
        {
            outCode[tp++] = cast(ubyte) finChar;
            i = oldCode;
        }
        else
            break; // corrupt LZW stream -- stop, keep what's decoded so far

        while (i >= colorMapSize)
        {
            if (i < freeCode)
            {
                outCode[tp++] = suffix[i];
                i = prefix[i];
            }
            else
                i = freeCode - 1; // shouldn't happen; FLTK clamps and continues
        }
        outCode[tp++] = cast(ubyte) i;
        finChar = i;

        do
        {
            tp--;
            image[p++] = outCode[tp];
            if (p >= eol)
            {
                if (!interlace) yc++;
                else
                    switch (pass)
                    {
                    case 0: yc += 8; if (yc >= height) { pass++; yc = 4; } break;
                    case 1: yc += 8; if (yc >= height) { pass++; yc = 2; } break;
                    case 2: yc += 4; if (yc >= height) { pass++; yc = 1; } break;
                    default: yc += 2; break; // pass 3
                    }
                if (yc >= height) yc = 0; // cheap bug fix on excess data, matches FLTK
                p = cast(size_t) yc * width;
                eol = p + width;
            }
        }
        while (tp > 0);

        if (oldCode != clearCode)
        {
            if (freeCode < 4096)
            {
                prefix[freeCode] = cast(short) oldCode;
                suffix[freeCode] = cast(ubyte) finChar;
                freeCode++;
            }
            if (freeCode > readMask && codeSize < 12)
            {
                codeSize++;
                readMask = (1 << codeSize) - 1;
            }
        }
        oldCode = curCode;
    }

    return true;
}

/*
 * Ported from `convert_to_xpm()` -- converts a pixel-index buffer plus
 * its color table into `fl.pixmap.Pixmap`'s "compressed colormap" XPM
 * rows (header, one packed-color-table row, then one pixel row per
 * image row). `transparentPixel < 0` means no transparency.
 */
private string[] convertToXpm(ubyte[] image, int width, int height,
    ref ubyte[256] cmapR, ref ubyte[256] cmapG, ref ubyte[256] cmapB,
    int colorMapSize, int transparentPixel)
{
    // The transparent pixel must be index 0 -- swap it into place if
    // it isn't (matches Pixmap.convertPixmap()'s own expectation that
    // the ' ' marker, assigned below to index 0's char, is always the
    // first color-table entry).
    if (transparentPixel > 0)
    {
        foreach (ref px; image)
        {
            if (px == transparentPixel) px = 0;
            else if (px == 0) px = cast(ubyte) transparentPixel;
        }
        import std.algorithm.mutation : swap;

        swap(cmapR[0], cmapR[transparentPixel]);
        swap(cmapG[0], cmapG[transparentPixel]);
        swap(cmapB[0], cmapB[transparentPixel]);
    }

    bool[256] used;
    foreach (px; image) used[px] = true;

    ubyte[256] remap;
    int base = (transparentPixel >= 0 && used[0]) ? ' ' : ' ' + 1;
    int numcolors = 0;
    foreach (i; 0 .. colorMapSize)
        if (used[i])
        {
            remap[i] = cast(ubyte)(base++);
            numcolors++;
        }

    auto table = new ubyte[4 * numcolors];
    size_t tp = 0;
    foreach (i; 0 .. colorMapSize)
        if (used[i])
        {
            table[tp++] = remap[i];
            table[tp++] = cmapR[i];
            table[tp++] = cmapG[i];
            table[tp++] = cmapB[i];
        }

    foreach (ref px; image) px = remap[px];

    auto rows = new string[height + 2];
    rows[0] = format("%d %d %d %d", width, height, -numcolors, 1);
    rows[1] = cast(string) table;
    foreach (y; 0 .. height)
        rows[2 + y] = cast(string)(image[y * width .. (y + 1) * width].dup);

    return rows;
}

unittest
{
    // A hand-built, byte-verified 2x1 GIF (no transparency): red
    // pixel, green pixel, uncompressed LZW (Clear, 0, 1, EOF at 3-bit
    // code width). See this module's own dev notes for the manual
    // bit-packing derivation.
    ubyte[] gif = [
        'G', 'I', 'F', '8', '9', 'a',
        2, 0, // screen width = 2
        1, 0, // screen height = 1
        0x80, // global color table, 2 colors
        0, // background color index
        0, // aspect ratio
        255, 0, 0, // color 0: red
        0, 255, 0, // color 1: green
        0x2c, // image descriptor
        0, 0, // left
        0, 0, // top
        2, 0, // width = 2
        1, 0, // height = 1
        0, // no local color table, no interlace
        2, // LZW min code size
        2, 0x44, 0x0A, // one data sub-block, 2 bytes
        0, // block terminator
        0x3b, // trailer
    ];

    auto img = new GifImage("mem", gif);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 1);

    import fl.pixmap : convertPixmap;
    import fl.enumerations : black;

    auto rgba = new ubyte[2 * 1 * 4];
    assert(convertPixmap(img.xpmData, rgba, black));
    assert(rgba[0 .. 4] == [255, 0, 0, 255]); // red, opaque
    assert(rgba[4 .. 8] == [0, 255, 0, 255]); // green, opaque
}

unittest
{
    // Same 2x1 image, but with a Graphic Control Extension marking
    // color index 1 (green) as transparent -- confirms the index-0
    // swap and the ' '-marker transparency path both work end to end.
    ubyte[] gif = [
        'G', 'I', 'F', '8', '9', 'a',
        2, 0,
        1, 0,
        0x80,
        0,
        0,
        255, 0, 0, // color 0: red
        0, 255, 0, // color 1: green (transparent)
        0x21, 0xF9, 4, // Graphic Control Extension
        0x01, // packed: transparent flag set
        0, 0, // delay
        1, // transparent color index = 1
        0, // block terminator
        0x2c,
        0, 0,
        0, 0,
        2, 0,
        1, 0,
        0,
        2,
        2, 0x44, 0x0A,
        0,
        0x3b,
    ];

    auto img = new GifImage("mem", gif);
    assert(!img.fail());
    assert(img.w() == 2 && img.h() == 1);

    import fl.pixmap : convertPixmap;
    import fl.enumerations : black;

    auto rgba = new ubyte[2 * 1 * 4];
    assert(convertPixmap(img.xpmData, rgba, black));
    assert(rgba[0 .. 4] == [255, 0, 0, 255]); // pixel 0 (red): opaque
    assert(rgba[4 .. 8][3] == 0); // pixel 1 (green, transparent): alpha 0
}

unittest
{
    // Failure modes: missing file (errFileAccess) and a malformed
    // signature (errFormat).
    auto missing = new GifImage("/nonexistent/path/does-not-exist.gif");
    assert(missing.fail() == Image.errFileAccess);

    auto bad = new GifImage("bad", [0, 1, 2, 3]);
    assert(bad.fail() == Image.errFormat);
}

unittest
{
    // A well-formed trailer with no image data at all reports errNoImage.
    ubyte[] gif = [
        'G', 'I', 'F', '8', '9', 'a',
        1, 0, 1, 0,
        0, // no global color table
        0, 0,
        0x3b, // trailer, no image descriptor ever seen
    ];
    auto empty = new GifImage("mem", gif);
    assert(empty.fail() == Image.errNoImage);
}

unittest
{
    // Multi-frame parsing (anim=true, via the protected load()):
    // onFrameData()/onExtensionData() fire once per block, with the
    // untouched (not convertToXpm()-mutated) per-frame palette.
    ubyte[] gif = [
        'G', 'I', 'F', '8', '9', 'a',
        2, 0, 1, 0,
        0x80, 0, 0,
        255, 0, 0, // color 0: red
        0, 255, 0, // color 1: green
        0x21, 0xFF, 11, // Application Extension, 11-byte app id block
        'N', 'E', 'T', 'S', 'C', 'A', 'P', 'E', '2', '.', '0',
        3, 1, 5, 0, // NETSCAPE sub-block: loop count = 5
        0, // terminator
        0x2c, 0, 0, 0, 0, 2, 0, 1, 0, 0, 2, 2, 0x44, 0x0A, 0, // frame 0: [0,1]
        0x2c, 0, 0, 0, 0, 2, 0, 1, 0, 0, 2, 2, 0x44, 0x0A, 0, // frame 1: [0,1]
        0x3b,
    ];

    static class Probe : GifImage
    {
        int frameCalls;
        int extCalls;
        int lastLoopCount = -1;

        this(string imagename, const(ubyte)[] data)
        {
            super();
            load(imagename, data, true);
        }

        override protected void onFrameData(ref GifFrame f)
        {
            frameCalls++;
            assert(f.w == 2 && f.h == 1);
            // clrs (and so cpal's length) is derived from the LZW code
            // size's bit depth, not the real color table's own entry
            // count -- matches FLTK's own "workaround for broken
            // GIF files" (ColorMapSize = 1 << BitsPerPixel,
            // unconditionally); min code size 2 here means clrs=4, two
            // more than the 2 real colors actually defined.
            assert(f.cpal.length == 4);
            assert(f.cpal[0] == Cpal(255, 0, 0)); // untouched -- not remapped to ' '
            assert(f.cpal[1] == Cpal(0, 255, 0));
            assert(f.bptr == [0, 1]);
        }

        override protected void onExtensionData(ref GifFrame f)
        {
            extCalls++;
            if (f.bptr.length >= 14 && f.bptr[0 .. 11] == "NETSCAPE2.0")
                lastLoopCount = f.bptr[12] | (f.bptr[13] << 8);
        }
    }

    auto probe = new Probe("mem", gif);
    assert(!probe.fail());
    assert(probe.frameCalls == 2);
    assert(probe.extCalls == 1);
    assert(probe.lastLoopCount == 5);
    // Frame 0 still produced real Pixmap/XPM data, same as the
    // non-anim path.
    assert(probe.w() == 2 && probe.h() == 1);
}
