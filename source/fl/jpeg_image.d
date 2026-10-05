/*
 * Ported from FL/Fl_JPEG_Image.H + src/Fl_JPEG_Image.cxx + src/
 * fl_write_jpeg.cxx (FLTK 1.5.0): Fl_JPEG_Image,
 * a JPEG file/buffer reader, plus the free fl_write_jpeg() writer
 * functions.
 *
 * JPEG decoding and encoding are done by `fl.jpeg_decoder` and
 * `fl.jpeg_encoder` (D implementations of the public-domain jpgd/jpge,
 * see those modules), not by libjpeg:
 *  - `decompressJpegFromMemory(buf, w, h, actualComps, 3)` (forcing
 *    `reqComps = 3`) always returns a tightly-packed RGB8 buffer
 *    regardless of whether the source JPEG was grayscale or color --
 *    exactly matching FLTK's own unconditional `dinfo.out_color_space =
 *    JCS_RGB` (libjpeg converts grayscale to RGB when asked), so
 *    `PngImage`-style per-color-type branching never comes up here.
 *  - `compressJpegToFile()` accepts `channels` 1 (grayscale), 3 (RGB) or
 *    4 (RGBA, alpha not stored), so a `d() == 4` `RGBImage` can be handed
 *    to the encoder as-is; only `d() == 2` (grayscale+alpha, not one of
 *    the encoder's three accepted shapes) needs a manual alpha-strip
 *    first. FLTK strips alpha for *both* d==2 and d==4 by hand, since
 *    raw libjpeg has no RGBA-input mode.
 *
 * Deliberate simplifications vs. FLTK, matching `writePng()`'s own
 * precedent:
 *  - `writeJpeg()`'s return code collapses FLTK's 5-way
 *    (`0`/`-1`/`-2`/`-3`/`-4`) convention to `0` (success), `-3`
 *    (invalid `d`, checked before ever calling the encoder, same
 *    condition FLTK checks), or `-2` (any other encode/file-write
 *    failure -- the encoder reports those as exceptions that do not
 *    distinguish "couldn't open the file" from "write failed" the way
 *    FLTK's own hand-rolled I/O does). `-1` ("jpeg library not
 *    available") never applies here, this port always has one.
 *  - JPEG quality is fixed at `fl.jpeg_encoder.JpegParams.init`'s default
 *    (85, H2V2 chroma subsampling) -- FLTK's own `fl_write_jpeg()` has no
 *    quality parameter either, so this isn't a narrowing.
 */
module fl.jpeg_image;

import fl.image : Image, RGBImage;
import fl.jpeg_decoder : decompressJpegFromMemory;
import fl.jpeg_encoder : compressJpegToFile, JpegParams;

/// Ported from `Fl_JPEG_Image` (`FL/Fl_JPEG_Image.H` + `src/
/// Fl_JPEG_Image.cxx`) -- a JPEG file/buffer reader, always decoding to
/// RGB8 (`d() == 3`) regardless of whether the source was grayscale or
/// color, matching FLTK's own unconditional `JCS_RGB` output.
class JpegImage : RGBImage
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
        loadJpeg(content);
    }

    /// Loads a JPEG image from an in-memory buffer -- e.g. data embedded
    /// at compile time via Fluid or similar. `name` is unused by this
    /// port, matching `fl.bmp_image.BMPImage`'s/`fl.png_image.PngImage`'s
    /// own equivalent constructors.
    this(string name, const(ubyte)[] data)
    {
        super(null, 0, 0);
        loadJpeg(data);
    }

    private void loadJpeg(const(ubyte)[] data)
    {
        int width, height, actualComps;
        ubyte[] pixels;
        try
            pixels = decompressJpegFromMemory(data, width, height, actualComps, 3);
        catch (Exception)
        {
            ld(errFormat);
            return;
        }

        array = pixels;
        w(width);
        h(height);
        d(3);
        ld(0);
        hasData(true);
    }
}

/**
 * Writes a raw pixel buffer to a JPEG file. Ported from
 * `fl_write_jpeg(const char*, const unsigned char*, int, int, int, int)`
 * (`src/fl_write_jpeg.cxx`) -- FLTK's separate `const char*`
 * overload collapses into this one D `const(ubyte)[]` overload, same
 * substitution used throughout this port for a raw-bytes parameter.
 *
 * `d` is the channel count (1 = grey, 2 = grey+alpha, 3 = RGB, 4 =
 * RGBA -- alpha is never stored in a JPEG, matching FLTK exactly);
 * `ld` is the row stride in bytes, `0` meaning tightly packed (`w * d`).
 *
 * Returns 0 on success, -3 if `d` is out of range, -2 on any other
 * encode/file-write failure -- see this module's own top comment for
 * why FLTK's fuller 5-way return-code convention collapses here.
 */
int writeJpeg(string filename, const(ubyte)[] pixels, int w, int h, int d = 3, int ld = 0)
{
    if (d < 1 || d > 4) return -3;
    if (ld == 0) ld = w * d;

    // Pack rows tightly first (the encoder has no stride concept),
    // then strip alpha for d==2 (the one shape the encoder doesn't
    // accept directly -- see this module's own top comment).
    int encodeChannels = (d == 2) ? 1 : d;
    auto packed = new ubyte[w * encodeChannels * h];
    foreach (row; 0 .. h)
    {
        auto src = pixels[row * ld .. row * ld + w * d];
        auto dst = packed[row * w * encodeChannels .. (row + 1) * w * encodeChannels];
        if (d == 2)
        {
            foreach (x; 0 .. w) dst[x] = src[x * 2]; // drop the alpha byte
        }
        else
        {
            dst[] = src[];
        }
    }

    try
        compressJpegToFile(filename, w, h, encodeChannels, packed, JpegParams.init);
    catch (Exception)
        return -2;
    return 0;
}

/// ditto -- ported from `fl_write_jpeg(const char*, Fl_RGB_Image*)`.
int writeJpeg(string filename, RGBImage img)
{
    return writeJpeg(filename, img.array, img.dataW(), img.dataH(), img.d(), img.ld());
}

// ---------------------------------------------------------------------
// Tests. JPEG is lossy, so unlike fl.png_image's exact round-trips,
// these compare against a tolerance (mean absolute per-byte difference)
// rather than requiring a byte-identical match.
// ---------------------------------------------------------------------

private double meanAbsDiff(const(ubyte)[] a, const(ubyte)[] b)
{
    import std.math : abs;
    long sum;
    foreach (i; 0 .. a.length) sum += abs(cast(int) a[i] - cast(int) b[i]);
    return cast(double) sum / a.length;
}

unittest
{
    import std.file : tempDir, remove, exists;
    import std.path : buildPath;

    // Smooth RGB gradient -- JPEG compresses this well, so a tight
    // tolerance still catches a genuinely broken encoder/decoder.
    int w = 40, h = 30;
    auto pixels = new ubyte[w * h * 3];
    foreach (y; 0 .. h)
        foreach (x; 0 .. w)
        {
            size_t off = (y * w + x) * 3;
            pixels[off + 0] = cast(ubyte)(x * 255 / w);
            pixels[off + 1] = cast(ubyte)(y * 255 / h);
            pixels[off + 2] = 128;
        }

    auto path = buildPath(tempDir(), "fldtk_jpeg_image_test.jpg");
    scope (exit) if (exists(path)) remove(path);

    assert(writeJpeg(path, pixels, w, h, 3, 0) == 0);

    auto img = new JpegImage(path);
    assert(img.fail() == 0);
    assert(img.w() == w && img.h() == h && img.d() == 3);
    assert(meanAbsDiff(pixels, img.array) < 8.0);
}

unittest
{
    import std.file : tempDir, remove, exists;
    import std.path : buildPath;

    // Grayscale (d=1) -- decoder always reports d()==3 (RGB), matching
    // FLTK's own unconditional JCS_RGB output; confirm R==G==B.
    int w = 20, h = 20;
    auto grey = new ubyte[w * h];
    foreach (i; 0 .. grey.length) grey[i] = cast(ubyte)(i * 255 / grey.length);

    auto path = buildPath(tempDir(), "fldtk_jpeg_image_grey_test.jpg");
    scope (exit) if (exists(path)) remove(path);

    assert(writeJpeg(path, grey, w, h, 1, 0) == 0);
    auto img = new JpegImage(path);
    assert(img.fail() == 0);
    assert(img.d() == 3);

    long sumAbsDiff;
    foreach (i; 0 .. grey.length)
    {
        int r = img.array[i * 3], g = img.array[i * 3 + 1], b = img.array[i * 3 + 2];
        assert(r == g && g == b); // truly grayscale, no color fringing
        sumAbsDiff += (r > grey[i]) ? r - grey[i] : grey[i] - r;
    }
    assert(cast(double) sumAbsDiff / grey.length < 8.0);
}

unittest
{
    import std.file : tempDir, remove, exists;
    import std.path : buildPath;

    // d==2 (grey+alpha) -- alpha silently dropped before encoding
    // (matches FLTK's own d==2 handling), still produces a valid
    // grayscale-looking JPEG.
    int w = 10, h = 10;
    auto greyAlpha = new ubyte[w * h * 2];
    foreach (i; 0 .. w * h) { greyAlpha[i * 2] = cast(ubyte)(i * 25); greyAlpha[i * 2 + 1] = 60; }

    auto path = buildPath(tempDir(), "fldtk_jpeg_image_greyalpha_test.jpg");
    scope (exit) if (exists(path)) remove(path);

    assert(writeJpeg(path, greyAlpha, w, h, 2, 0) == 0);
    auto img = new JpegImage(path);
    assert(img.fail() == 0 && img.w() == w && img.h() == h && img.d() == 3);
}

unittest
{
    // writeJpeg() rejects an out-of-range depth up front.
    ubyte[] pixels = [0, 0, 0];
    assert(writeJpeg("/tmp/unused.jpg", pixels, 1, 1, 5, 0) == -3);
    assert(writeJpeg("/tmp/unused.jpg", pixels, 1, 1, 0, 0) == -3);
}

unittest
{
    // Malformed input reports errFormat, doesn't throw.
    auto img = new JpegImage("bad", cast(const(ubyte)[]) [1, 2, 3, 4]);
    assert(img.fail() == Image.errFormat);
}

unittest
{
    // A missing file reports errFileAccess, doesn't throw.
    auto img = new JpegImage("/nonexistent/path/does-not-exist.jpg");
    assert(img.fail() == Image.errFileAccess);
}
