/*
 * JPEG encoder: baseline sequential-DCT JPEG with Huffman coding, from 8-bit
 * grayscale, RGB or RGBA pixels, with optional 2x chroma subsampling and
 * optimized Huffman tables. The alpha channel is not stored.
 *
 * This is a D implementation of Rich Geldreich's public-domain (Unlicense)
 * jpge, following Ketmar's D translation in Adam D. Ruppe's `arsd`
 * collection (`arsd/jpeg.d`), and it produces the same file, byte for byte,
 * as that encoder for the same pixels and parameters. In the default
 * two-pass mode every pixel is run through the DCT twice: the first pass
 * gathers the symbol statistics the optimized Huffman tables are built
 * from, the second writes the file.
 *
 * `compressJpegToMemory()` and friends are the usual entry points;
 * `JpegEncoder` gives line-wise control. Failures are reported by throwing
 * (`JpegException` for bad arguments, whatever the write delegate throws
 * for I/O errors).
 */
module fl.jpeg_encoder;

import fl.jpeg_common;
import std.algorithm.mutation : SwapStrategy;
import std.algorithm.sorting : sort;
import std.stdio : File;

/// Chroma subsampling of the encoded image. `yOnly` (grayscale) and `h2v2`
/// (color; the most common choice) are the usual ones.
enum JpegSubsampling
{
    yOnly = 0, /// Y only: a grayscale JPEG
    h1v1 = 1, /// YCbCr, no subsampling: 3 blocks per MCU
    h2v1 = 2, /// YCbCr, chroma halved horizontally: 4 blocks per MCU
    h2v2 = 3, /// YCbCr, chroma halved both ways: 6 blocks per MCU
}

/// JPEG compression parameters.
struct JpegParams
{
    /// Quality, 1-100: higher is better. Typical values are around 50-95.
    int quality = 85;

    /// Chroma subsampling.
    JpegSubsampling subsampling = JpegSubsampling.h2v2;

    /// If true the Y quantization table is used for the chroma channels
    /// too; only intended for testing.
    bool noChromaDiscrim = false;

    /// Build optimized Huffman tables (the file is smaller; the image is
    /// processed twice).
    bool twoPass = true;

    /// Whether the values are in range.
    bool check() const pure nothrow @safe @nogc
    {
        if (quality < 1 || quality > 100)
            return false;
        if (cast(uint) subsampling > cast(uint) JpegSubsampling.h2v2)
            return false;
        return true;
    }
}

/// Receives the encoded data in pieces; throws to report a write error.
alias JpegWriteFunc = void delegate(const(ubyte)[] data);

// ---------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------

private enum dcLumCodes = 12, acLumCodes = 256, dcChromaCodes = 12, acChromaCodes = 256;
private enum maxHuffSymbols = 257;
private enum maxHuffCodeSize = 32;

// The standard quantization tables, in zig-zag order.
private static immutable short[64] stdLumQuant = [
    16, 11, 12, 14, 12, 10, 16, 14, 13, 14, 18, 17, 16, 19, 24, 40,
    26, 24, 22, 22, 24, 49, 35, 37, 29, 40, 58, 51, 61, 60, 57, 51,
    56, 55, 64, 72, 92, 78, 64, 68, 87, 69, 55, 56, 80, 109, 81, 87,
    95, 98, 103, 104, 103, 62, 77, 113, 121, 112, 100, 120, 92, 101, 103, 99,
];
private static immutable short[64] stdChromaQuant = [
    17, 18, 18, 24, 21, 24, 47, 26, 26, 47, 99, 66, 56, 66, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
];

// The standard Huffman tables (used when the tables are not optimized).
private static immutable ubyte[17] stdDcLumBits = [0, 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
private static immutable ubyte[dcLumCodes] stdDcLumVal = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
private static immutable ubyte[17] stdAcLumBits = [0, 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d];
private static immutable ubyte[acLumCodes] stdAcLumVal = [
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
    0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
];
private static immutable ubyte[17] stdDcChromaBits = [0, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0];
private static immutable ubyte[dcChromaCodes] stdDcChromaVal = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
private static immutable ubyte[17] stdAcChromaBits = [0, 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77];
private static immutable ubyte[acChromaCodes] stdAcChromaVal = [
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
    0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
    0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
    0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
    0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
];

// ---------------------------------------------------------------------
// Color conversion
// ---------------------------------------------------------------------

// RGB to YCbCr, 16.16 fixed point.
private enum yr = 19595, yg = 38470, yb = 7471;
private enum cbR = -11059, cbG = -21709, cbB = 32768;
private enum crR = 32768, crG = -27439, crB = -5329;

/// Converts `numPixels` pixels of `src` (`srcPitch` bytes per pixel,
/// 3 or 4: RGB or RGBA) to Y, Cb, Cr triples in `dst`.
private void rgbToYcc(ubyte[] dst, const(ubyte)[] src, int srcPitch, int numPixels)
    pure nothrow @safe @nogc
{
    foreach (i; 0 .. numPixels)
    {
        immutable int r = src[i * srcPitch], g = src[i * srcPitch + 1], b = src[i * srcPitch + 2];
        dst[i * 3] = cast(ubyte)((r * yr + g * yg + b * yb + 32768) >> 16);
        dst[i * 3 + 1] = clampByte(128 + ((r * cbR + g * cbG + b * cbB + 32768) >> 16));
        dst[i * 3 + 2] = clampByte(128 + ((r * crR + g * crG + b * crB + 32768) >> 16));
    }
}

/// Converts `numPixels` pixels of `src` (3 or 4 bytes per pixel) to Y.
private void rgbToY(ubyte[] dst, const(ubyte)[] src, int srcPitch, int numPixels)
    pure nothrow @safe @nogc
{
    foreach (i; 0 .. numPixels)
        dst[i] = cast(ubyte)((src[i * srcPitch] * yr + src[i * srcPitch + 1] * yg
            + src[i * srcPitch + 2] * yb + 32768) >> 16);
}

/// Expands `numPixels` gray pixels to Y, Cb, Cr triples.
private void grayToYcc(ubyte[] dst, const(ubyte)[] src, int numPixels) pure nothrow @safe @nogc
{
    foreach (i; 0 .. numPixels)
    {
        dst[i * 3] = src[i];
        dst[i * 3 + 1] = 128;
        dst[i * 3 + 2] = 128;
    }
}

// ---------------------------------------------------------------------
// Forward DCT (derived from the IJG jfdctint algorithm)
// ---------------------------------------------------------------------

private enum rowBits = 2;

private int dctDescale(int x, int n) pure nothrow @safe @nogc
{
    return (x + (1 << (n - 1))) >> n;
}

/// One 8-point forward DCT butterfly, in place. The partial sums are
/// deliberately truncated to 16 bits before the multiplications.
private void fdct1d(ref int[8] s) pure nothrow @safe @nogc
{
    immutable int t0 = s[0] + s[7], t7 = s[0] - s[7];
    immutable int t1 = s[1] + s[6], t6 = s[1] - s[6];
    immutable int t2 = s[2] + s[5], t5 = s[2] - s[5];
    immutable int t3 = s[3] + s[4], t4 = s[3] - s[4];

    immutable int t10 = t0 + t3, t13 = t0 - t3, t11 = t1 + t2, t12 = t1 - t2;

    immutable int e1 = cast(short)(t12 + t13) * 4433;
    s[2] = e1 + cast(short)(t13) * 6270;
    s[6] = e1 + cast(short)(t12) * -15137;

    int u1 = t4 + t7;
    int u2 = t5 + t6, u3 = t4 + t6, u4 = t5 + t7;
    immutable int z5 = cast(short)(u3 + u4) * 9633;

    immutable int v4 = cast(short)(t4) * 2446;
    immutable int v5 = cast(short)(t5) * 16819;
    immutable int v6 = cast(short)(t6) * 25172;
    immutable int v7 = cast(short)(t7) * 12299;

    u1 = cast(short)(u1) * -7373;
    u2 = cast(short)(u2) * -20995;
    u3 = cast(short)(u3) * -16069;
    u4 = cast(short)(u4) * -3196;
    u3 += z5;
    u4 += z5;

    s[0] = t10 + t11;
    s[1] = v7 + u1 + u4;
    s[3] = v6 + u2 + u3;
    s[4] = t10 - t11;
    s[5] = v5 + u2 + u4;
    s[7] = v4 + u1 + u3;
}

/// Two-dimensional forward DCT of an 8x8 block of samples, in place. The
/// rows and columns are unrolled so that every array index is a constant.
private void fdct2d(ref int[64] p) pure nothrow @safe @nogc
{
    int[8] s = void;

    static foreach (r; 0 .. 8)
    {
        {
            static foreach (k; 0 .. 8)
                s[k] = p[r * 8 + k];
            fdct1d(s);
            p[r * 8 + 0] = s[0] << rowBits;
            p[r * 8 + 4] = s[4] << rowBits;
            static foreach (k; [1, 2, 3, 5, 6, 7])
                p[r * 8 + k] = dctDescale(s[k], constBits - rowBits);
        }
    }

    static foreach (c; 0 .. 8)
    {
        {
            static foreach (k; 0 .. 8)
                s[k] = p[k * 8 + c];
            fdct1d(s);
            p[0 * 8 + c] = dctDescale(s[0], rowBits + 3);
            p[4 * 8 + c] = dctDescale(s[4], rowBits + 3);
            static foreach (k; [1, 2, 3, 5, 6, 7])
                p[k * 8 + c] = dctDescale(s[k], constBits + rowBits + 3);
        }
    }
}

// ---------------------------------------------------------------------
// Huffman code construction
// ---------------------------------------------------------------------

private struct SymFreq
{
    uint key; // frequency, then (after calculateMinimumRedundancy) code size
    uint symIndex;
}

/// Computes the code size of each symbol of `a` (sorted by increasing
/// frequency, which is stored in `key`) and stores it in `key`.
///
/// Originally written by Alistair Moffat and Jyrki Katajainen (November
/// 1996), "In-place calculation of minimum-redundancy codes".
private void calculateMinimumRedundancy(SymFreq[] a) pure nothrow @safe @nogc
{
    immutable int n = cast(int) a.length;
    if (n == 0)
        return;
    if (n == 1)
    {
        a[0].key = 1;
        return;
    }

    int root, leaf, next;
    a[0].key += a[1].key;
    root = 0;
    leaf = 2;
    for (next = 1; next < n - 1; next++)
    {
        if (leaf >= n || a[root].key < a[leaf].key)
        {
            a[next].key = a[root].key;
            a[root++].key = next;
        }
        else
            a[next].key = a[leaf++].key;

        if (leaf >= n || (root < next && a[root].key < a[leaf].key))
        {
            a[next].key += a[root].key;
            a[root++].key = next;
        }
        else
            a[next].key += a[leaf++].key;
    }

    a[n - 2].key = 0;
    for (next = n - 3; next >= 0; next--)
        a[next].key = a[a[next].key].key + 1;

    int avbl = 1, used = 0, dpth = 0;
    root = n - 2;
    next = n - 1;
    while (avbl > 0)
    {
        while (root >= 0 && cast(int) a[root].key == dpth)
        {
            used++;
            root--;
        }
        while (avbl > used)
        {
            a[next--].key = dpth;
            avbl--;
        }
        avbl = 2 * used;
        dpth++;
        used = 0;
    }
}

/// Limits a canonical Huffman code table's maximum code size to
/// `maxCodeSize`. `numCodes[i]` is the number of codes of size `i`.
private void enforceMaxCodeSize(int[] numCodes, int codeListLen, int maxCodeSize) pure nothrow @safe @nogc
{
    if (codeListLen <= 1)
        return;

    foreach (i; maxCodeSize + 1 .. maxHuffCodeSize + 1)
        numCodes[maxCodeSize] += numCodes[i];

    uint total = 0;
    for (int i = maxCodeSize; i > 0; i--)
        total += (cast(uint) numCodes[i]) << (maxCodeSize - i);

    while (total != (1UL << maxCodeSize))
    {
        numCodes[maxCodeSize]--;
        for (int i = maxCodeSize - 1; i > 0; i--)
        {
            if (numCodes[i])
            {
                numCodes[i]--;
                numCodes[i + 1] += 2;
                break;
            }
        }
        total--;
    }
}

/// One Huffman table: its definition (`bits`, `val`), the symbol counts
/// gathered in the first pass, and the codes derived for writing.
private struct HuffEncTable
{
    ubyte[17] bits; // bits[l] = number of codes of length l
    ubyte[256] val; // symbols in order of increasing code length
    uint[256] count; // symbol frequencies (first pass)
    uint[256] codes;
    ubyte[256] codeSizes;

    /// Builds the optimal table for the gathered counts.
    void optimize(int tableLen)
    {
        SymFreq[maxHuffSymbols] syms = void;
        syms[0] = SymFreq(1, 0); // dummy symbol, assures that no valid code contains all 1's
        int numUsedSyms = 1;
        foreach (i; 0 .. tableLen)
        {
            if (count[i])
                syms[numUsedSyms++] = SymFreq(count[i], i + 1);
        }

        // Sort by increasing frequency, equal frequencies keeping their order.
        auto used = syms[0 .. numUsedSyms];
        used.sort!((a, b) => a.key < b.key, SwapStrategy.stable)();
        calculateMinimumRedundancy(used);

        // Count the number of symbols of each code size.
        int[1 + maxHuffCodeSize] numCodes;
        foreach (ref sym; used)
            numCodes[sym.key > maxHuffCodeSize ? maxHuffCodeSize : sym.key]++;

        // The maximum possible size of a JPEG Huffman code is 16 (the valid
        // range here is [9,16]: 9 rather than 8 because of the dummy symbol).
        enum codeSizeLimit = 16;
        enforceMaxCodeSize(numCodes[], numUsedSyms, codeSizeLimit);

        // The number of symbols per code size.
        bits[] = 0;
        foreach (i; 1 .. codeSizeLimit + 1)
            bits[i] = cast(ubyte) numCodes[i];

        // Remove the dummy symbol added above, which must be in the largest bucket.
        for (int i = codeSizeLimit; i >= 1; i--)
        {
            if (bits[i])
            {
                bits[i]--;
                break;
            }
        }

        // The symbols sorted by code size (smallest to largest).
        for (int i = numUsedSyms - 1; i >= 1; i--)
            val[numUsedSyms - 1 - i] = cast(ubyte)(used[i].symIndex - 1);
    }

    /// Computes the actual canonical codes and code sizes from `bits` and `val`.
    void computeCodes()
    {
        ubyte[257] huffSize;
        uint[257] huffCode;

        int p = 0;
        foreach (l; 1 .. 17)
            foreach (i; 1 .. bits[l] + 1)
                huffSize[p++] = cast(ubyte) l;
        huffSize[p] = 0; // sentinel
        immutable int lastP = p;

        uint code = 0;
        int si = huffSize[0];
        p = 0;
        while (huffSize[p])
        {
            while (huffSize[p] == si)
                huffCode[p++] = code++;
            code <<= 1;
            si++;
        }

        codes[] = 0;
        codeSizes[] = 0;
        foreach (i; 0 .. lastP)
        {
            codes[val[i]] = huffCode[i];
            codeSizes[val[i]] = huffSize[i];
        }
    }

    /// Makes this the given standard table.
    void setStandard(const ubyte[17] stdBits, const(ubyte)[] stdVal)
    {
        bits = stdBits;
        val[0 .. stdVal.length] = stdVal[];
    }
}

// ---------------------------------------------------------------------
// The encoder
// ---------------------------------------------------------------------

/// Encodes an image into a JPEG stream one scan line at a time.
///
/// Create it, then for each pass (`totalPasses`: 2, or 1 without optimized
/// Huffman tables) feed all `height` scan lines to `processScanline()` and
/// call `endPass()`. The JPEG data goes to the write delegate, in pieces,
/// as it is produced.
final class JpegEncoder
{
    private
    {
        enum outBufSize = 2048;

        JpegWriteFunc write_;
        JpegParams params_;
        int numComponents_; // 1 or 3
        int[3] compHSamp_, compVSamp_;
        int imageX_, imageY_, imageBpp_;
        int imageXMcu_;
        int imageBplXlt_; // bytes per line after color conversion
        int imageBplMcu_; // the same, padded to a whole number of MCUs
        int mcusPerRow_;
        int mcuX_, mcuY_;
        ubyte[] mcuBuf_; // the lines of one MCU row
        int mcuYOfs_; // lines of the current MCU row loaded so far
        int[64] sampleArray_;
        short[64] coefficientArray_;
        int[64][2] quantTables_;
        HuffEncTable[2] dcTables_, acTables_; // luma, chroma
        int[3] lastDcVal_;
        ubyte[] outBuf_;
        size_t outLen_;
        uint bitBuffer_;
        uint bitsIn_;
        int passNum_; // 1 or 2
        bool finished_;
    }

    /// Prepares to encode an image `width` by `height` pixels with
    /// `channels` (1, 3 or 4) bytes per pixel to `write`. Throws
    /// `JpegException` if an argument is out of range.
    this(JpegWriteFunc write, int width, int height, int channels, JpegParams params = JpegParams.init)
    {
        if (write is null || width < 1 || height < 1 || (channels != 1 && channels != 3 && channels != 4)
            || !params.check())
            throw new JpegException(JpegStatus.badArguments);
        write_ = write;
        params_ = params;

        numComponents_ = 3;
        final switch (params_.subsampling)
        {
        case JpegSubsampling.yOnly:
            numComponents_ = 1;
            compHSamp_[0] = 1;
            compVSamp_[0] = 1;
            mcuX_ = 8;
            mcuY_ = 8;
            break;
        case JpegSubsampling.h1v1:
            compHSamp_ = [1, 1, 1];
            compVSamp_ = [1, 1, 1];
            mcuX_ = 8;
            mcuY_ = 8;
            break;
        case JpegSubsampling.h2v1:
            compHSamp_ = [2, 1, 1];
            compVSamp_ = [1, 1, 1];
            mcuX_ = 16;
            mcuY_ = 8;
            break;
        case JpegSubsampling.h2v2:
            compHSamp_ = [2, 1, 1];
            compVSamp_ = [2, 1, 1];
            mcuX_ = 16;
            mcuY_ = 16;
            break;
        }

        imageX_ = width;
        imageY_ = height;
        imageBpp_ = channels;
        imageXMcu_ = (imageX_ + mcuX_ - 1) & ~(mcuX_ - 1);
        imageBplXlt_ = imageX_ * numComponents_;
        imageBplMcu_ = imageXMcu_ * numComponents_;
        mcusPerRow_ = imageXMcu_ / mcuX_;

        mcuBuf_ = new ubyte[](imageBplMcu_ * mcuY_);

        computeQuantTable(quantTables_[0], stdLumQuant);
        computeQuantTable(quantTables_[1], params_.noChromaDiscrim ? stdLumQuant : stdChromaQuant);

        outBuf_ = new ubyte[](outBufSize);

        if (params_.twoPass)
            firstPassInit();
        else
        {
            dcTables_[0].setStandard(stdDcLumBits, stdDcLumVal[]);
            acTables_[0].setStandard(stdAcLumBits, stdAcLumVal[]);
            dcTables_[1].setStandard(stdDcChromaBits, stdDcChromaVal[]);
            acTables_[1].setStandard(stdAcChromaBits, stdAcChromaVal[]);
            secondPassInit(); // in effect, skip over the first pass
        }
    }

    /// How many times the whole image has to be fed in: 2 with optimized
    /// Huffman tables, otherwise 1.
    uint totalPasses() const pure nothrow @safe @nogc
    {
        return params_.twoPass ? 2 : 1;
    }

    /// Feeds the next scan line: `width * channels` bytes (Y, RGB or RGBA).
    void processScanline(const(ubyte)[] line)
    {
        if (finished_ || line.length < cast(size_t) imageX_ * imageBpp_)
            throw new JpegException(JpegStatus.badArguments);
        loadMcuLine(line);
    }

    /// Ends the current pass, after all scan lines were fed in. After the
    /// last pass the JPEG file is complete.
    void endPass()
    {
        if (finished_)
            throw new JpegException(JpegStatus.badArguments);

        if (mcuYOfs_)
        {
            // Duplicate the last line to fill up the last MCU row.
            foreach (i; mcuYOfs_ .. mcuY_)
                mcuLine(i)[] = mcuLine(mcuYOfs_ - 1)[];
            processMcuRow();
        }

        if (passNum_ == 1)
            terminatePassOne();
        else
            terminatePassTwo();
    }

private:
    ubyte[] mcuLine(int i)
    {
        return mcuBuf_[cast(size_t) i * imageBplMcu_ .. cast(size_t)(i + 1) * imageBplMcu_];
    }

    // -----------------------------------------------------------------
    // Output
    // -----------------------------------------------------------------

    void flushOutput()
    {
        if (outLen_)
        {
            immutable size_t n = outLen_;
            outLen_ = 0;
            write_(outBuf_[0 .. n]);
        }
    }

    void emitByte(int i)
    {
        outBuf_[outLen_++] = cast(ubyte) i;
        if (outLen_ == outBuf_.length)
            flushOutput();
    }

    void emitWord(uint i)
    {
        emitByte(i >> 8);
        emitByte(i & 0xFF);
    }

    void emitMarker(int marker)
    {
        emitByte(0xFF);
        emitByte(marker);
    }

    void putBits(uint bits, uint len)
    {
        bitBuffer_ |= bits << (24 - (bitsIn_ += len));
        while (bitsIn_ >= 8)
        {
            immutable ubyte c = cast(ubyte)((bitBuffer_ >> 16) & 0xFF);
            emitByte(c);
            if (c == 0xFF)
                emitByte(0); // stuff a zero after any 0xFF
            bitBuffer_ <<= 8;
            bitsIn_ -= 8;
        }
    }

    // -----------------------------------------------------------------
    // Markers
    // -----------------------------------------------------------------

    /// Emits the JFIF marker.
    void emitJfifApp0()
    {
        emitMarker(JpegMarker.app0);
        emitWord(2 + 4 + 1 + 2 + 1 + 2 + 2 + 1 + 1);
        foreach (c; "JFIF")
            emitByte(c);
        emitByte(0);
        emitByte(1); // major version
        emitByte(1); // minor version
        emitByte(0); // density unit
        emitWord(1);
        emitWord(1);
        emitByte(0); // no thumbnail image
        emitByte(0);
    }

    /// Emits the quantization tables.
    void emitDqt()
    {
        foreach (i; 0 .. (numComponents_ == 3 ? 2 : 1))
        {
            emitMarker(JpegMarker.dqt);
            emitWord(64 + 1 + 2);
            emitByte(i);
            foreach (j; 0 .. 64)
                emitByte(quantTables_[i][j]);
        }
    }

    /// Emits the start-of-frame marker.
    void emitSof()
    {
        emitMarker(JpegMarker.sof0); // baseline
        emitWord(3 * numComponents_ + 2 + 5 + 1);
        emitByte(8); // precision
        emitWord(imageY_);
        emitWord(imageX_);
        emitByte(numComponents_);
        foreach (i; 0 .. numComponents_)
        {
            emitByte(i + 1); // component ID
            emitByte((compHSamp_[i] << 4) + compVSamp_[i]); // h and v sampling
            emitByte(i > 0); // quantization table number
        }
    }

    /// Emits a Huffman table definition.
    void emitDht(ref const HuffEncTable t, int index, bool acFlag)
    {
        emitMarker(JpegMarker.dht);
        int length = 0;
        foreach (i; 1 .. 17)
            length += t.bits[i];
        emitWord(length + 2 + 1 + 16);
        emitByte(index + (acFlag << 4));
        foreach (i; 1 .. 17)
            emitByte(t.bits[i]);
        foreach (i; 0 .. length)
            emitByte(t.val[i]);
    }

    /// Emits all Huffman tables.
    void emitDhts()
    {
        emitDht(dcTables_[0], 0, false);
        emitDht(acTables_[0], 0, true);
        if (numComponents_ == 3)
        {
            emitDht(dcTables_[1], 1, false);
            emitDht(acTables_[1], 1, true);
        }
    }

    /// Emits the start-of-scan marker.
    void emitSos()
    {
        emitMarker(JpegMarker.sos);
        emitWord(2 * numComponents_ + 2 + 1 + 3);
        emitByte(numComponents_);
        foreach (i; 0 .. numComponents_)
        {
            emitByte(i + 1);
            emitByte(i == 0 ? 0x00 : 0x11); // DC and AC table numbers
        }
        emitByte(0); // spectral selection
        emitByte(63);
        emitByte(0);
    }

    /// Emits all markers at the beginning of the file.
    void emitMarkers()
    {
        emitMarker(JpegMarker.soi);
        emitJfifApp0();
        emitDqt();
        emitSof();
        emitDhts();
        emitSos();
    }

    // -----------------------------------------------------------------
    // Passes
    // -----------------------------------------------------------------

    /// Computes a quantization table (in zig-zag order) for the quality.
    void computeQuantTable(ref int[64] dst, const short[64] src)
    {
        immutable int q = params_.quality < 50 ? 5000 / params_.quality : 200 - params_.quality * 2;
        foreach (i; 0 .. 64)
        {
            immutable int j = (src[i] * q + 50) / 100;
            dst[i] = j < 1 ? 1 : (j > 255 ? 255 : j);
        }
    }

    void firstPassInit()
    {
        bitBuffer_ = 0;
        bitsIn_ = 0;
        lastDcVal_[] = 0;
        mcuYOfs_ = 0;
        passNum_ = 1;
    }

    void secondPassInit()
    {
        dcTables_[0].computeCodes();
        acTables_[0].computeCodes();
        if (numComponents_ > 1)
        {
            dcTables_[1].computeCodes();
            acTables_[1].computeCodes();
        }
        firstPassInit();
        emitMarkers();
        passNum_ = 2;
    }

    void terminatePassOne()
    {
        dcTables_[0].optimize(dcLumCodes);
        acTables_[0].optimize(acLumCodes);
        if (numComponents_ > 1)
        {
            dcTables_[1].optimize(dcChromaCodes);
            acTables_[1].optimize(acChromaCodes);
        }
        secondPassInit();
    }

    void terminatePassTwo()
    {
        putBits(0x7F, 7);
        flushOutput();
        emitMarker(JpegMarker.eoi);
        flushOutput();
        finished_ = true;
    }

    // -----------------------------------------------------------------
    // Loading lines and blocks
    // -----------------------------------------------------------------

    /// Converts a source line into the next line of the MCU row.
    void loadMcuLine(const(ubyte)[] src)
    {
        ubyte[] dst = mcuLine(mcuYOfs_);

        if (numComponents_ == 1)
        {
            if (imageBpp_ == 1)
                dst[0 .. imageX_] = src[0 .. imageX_];
            else
                rgbToY(dst, src, imageBpp_, imageX_);
        }
        else
        {
            if (imageBpp_ == 1)
                grayToYcc(dst, src, imageX_);
            else
                rgbToYcc(dst, src, imageBpp_, imageX_);
        }

        // Duplicate the last pixel to the end of the line, if the width is
        // not a multiple of 8 or 16.
        if (numComponents_ == 1)
            dst[imageBplXlt_ .. imageBplMcu_] = dst[imageBplXlt_ - 1];
        else
        {
            foreach (i; imageX_ .. imageXMcu_)
                dst[i * 3 .. i * 3 + 3] = dst[imageBplXlt_ - 3 .. imageBplXlt_];
        }

        if (++mcuYOfs_ == mcuY_)
        {
            processMcuRow();
            mcuYOfs_ = 0;
        }
    }

    /// Loads the 8x8 block `x` of a grayscale image.
    void loadBlock8x8Gray(int x)
    {
        x <<= 3;
        foreach (i; 0 .. 8)
        {
            const(ubyte)[] src = mcuLine(i)[x .. x + 8];
            foreach (k; 0 .. 8)
                sampleArray_[i * 8 + k] = src[k] - 128;
        }
    }

    /// Loads the 8x8 block (`bx`, `by`) of component `c` of a color image
    /// (no subsampling).
    void loadBlock8x8(int bx, int by, int c)
    {
        immutable int x = bx * (8 * 3) + c;
        by <<= 3;
        foreach (i; 0 .. 8)
        {
            const(ubyte)[] src = mcuLine(by + i);
            foreach (k; 0 .. 8)
                sampleArray_[i * 8 + k] = src[x + k * 3] - 128;
        }
    }

    /// Loads a chroma block of an H2V2 image: each sample is the average
    /// of 2x2 pixels, with an ordered dither of the rounding.
    void loadBlock16x8(int bx, int c)
    {
        immutable int x = bx * (16 * 3) + c;
        foreach (i; 0 .. 8)
        {
            const(ubyte)[] src1 = mcuLine(2 * i);
            const(ubyte)[] src2 = mcuLine(2 * i + 1);
            foreach (k; 0 .. 8)
            {
                immutable int dither = ((k + i) & 1) ? 2 : 0;
                sampleArray_[i * 8 + k] = ((src1[x + 2 * k * 3] + src1[x + (2 * k + 1) * 3]
                    + src2[x + 2 * k * 3] + src2[x + (2 * k + 1) * 3] + dither) >> 2) - 128;
            }
        }
    }

    /// Loads a chroma block of an H2V1 image: each sample is the average
    /// of 2 horizontal pixels.
    void loadBlock16x8x8(int bx, int c)
    {
        immutable int x = bx * (16 * 3) + c;
        foreach (i; 0 .. 8)
        {
            const(ubyte)[] src = mcuLine(i);
            foreach (k; 0 .. 8)
                sampleArray_[i * 8 + k] = ((src[x + 2 * k * 3] + src[x + (2 * k + 1) * 3]) >> 1) - 128;
        }
    }

    // -----------------------------------------------------------------
    // Coding blocks
    // -----------------------------------------------------------------

    /// Quantizes the transformed block into `coefficientArray_`, in zig-zag order.
    void loadQuantizedCoefficients(int componentNum)
    {
        ref const int[64] q = quantTables_[componentNum > 0];
        foreach (i; 0 .. 64)
        {
            int j = sampleArray_[zigzag[i]];
            if (j < 0)
            {
                if ((j = -j + (q[i] >> 1)) < q[i])
                    coefficientArray_[i] = 0;
                else
                    coefficientArray_[i] = cast(short)(-(j / q[i]));
            }
            else
            {
                if ((j = j + (q[i] >> 1)) < q[i])
                    coefficientArray_[i] = 0;
                else
                    coefficientArray_[i] = cast(short)(j / q[i]);
            }
        }
    }

    /// First pass: counts the Huffman symbols the block needs.
    void codeCoefficientsPassOne(int componentNum)
    {
        uint[] dcCount = dcTables_[componentNum > 0].count[];
        uint[] acCount = acTables_[componentNum > 0].count[];

        int temp1 = coefficientArray_[0] - lastDcVal_[componentNum];
        lastDcVal_[componentNum] = coefficientArray_[0];
        if (temp1 < 0)
            temp1 = -temp1;

        int nbits = 0;
        while (temp1)
        {
            nbits++;
            temp1 >>= 1;
        }

        dcCount[nbits]++;

        int runLen = 0;
        foreach (i; 1 .. 64)
        {
            if ((temp1 = coefficientArray_[i]) == 0)
                runLen++;
            else
            {
                while (runLen >= 16)
                {
                    acCount[0xF0]++;
                    runLen -= 16;
                }
                if (temp1 < 0)
                    temp1 = -temp1;
                nbits = 1;
                while (temp1 >>= 1)
                    nbits++;
                acCount[(runLen << 4) + nbits]++;
                runLen = 0;
            }
        }
        if (runLen)
            acCount[0]++;
    }

    /// Second pass: writes the Huffman-coded block.
    void codeCoefficientsPassTwo(int componentNum)
    {
        ref const HuffEncTable dc = dcTables_[componentNum > 0];
        ref const HuffEncTable ac = acTables_[componentNum > 0];

        int temp1 = coefficientArray_[0] - lastDcVal_[componentNum];
        int temp2 = temp1;
        lastDcVal_[componentNum] = coefficientArray_[0];

        if (temp1 < 0)
        {
            temp1 = -temp1;
            temp2--;
        }

        int nbits = 0;
        while (temp1)
        {
            nbits++;
            temp1 >>= 1;
        }

        putBits(dc.codes[nbits], dc.codeSizes[nbits]);
        if (nbits)
            putBits(temp2 & ((1 << nbits) - 1), nbits);

        int runLen = 0;
        foreach (i; 1 .. 64)
        {
            if ((temp1 = coefficientArray_[i]) == 0)
                runLen++;
            else
            {
                while (runLen >= 16)
                {
                    putBits(ac.codes[0xF0], ac.codeSizes[0xF0]);
                    runLen -= 16;
                }
                if ((temp2 = temp1) < 0)
                {
                    temp1 = -temp1;
                    temp2--;
                }
                nbits = 1;
                while (temp1 >>= 1)
                    nbits++;
                immutable int j = (runLen << 4) + nbits;
                putBits(ac.codes[j], ac.codeSizes[j]);
                putBits(temp2 & ((1 << nbits) - 1), nbits);
                runLen = 0;
            }
        }
        if (runLen)
            putBits(ac.codes[0], ac.codeSizes[0]);
    }

    void codeBlock(int componentNum)
    {
        fdct2d(sampleArray_);
        loadQuantizedCoefficients(componentNum);
        if (passNum_ == 1)
            codeCoefficientsPassOne(componentNum);
        else
            codeCoefficientsPassTwo(componentNum);
    }

    /// Codes all the blocks of the MCU row held in `mcuBuf_`.
    void processMcuRow()
    {
        if (numComponents_ == 1)
        {
            foreach (i; 0 .. mcusPerRow_)
            {
                loadBlock8x8Gray(i);
                codeBlock(0);
            }
        }
        else if (compHSamp_[0] == 1 && compVSamp_[0] == 1)
        {
            foreach (i; 0 .. mcusPerRow_)
            {
                foreach (c; 0 .. 3)
                {
                    loadBlock8x8(i, 0, c);
                    codeBlock(c);
                }
            }
        }
        else if (compHSamp_[0] == 2 && compVSamp_[0] == 1)
        {
            foreach (i; 0 .. mcusPerRow_)
            {
                loadBlock8x8(i * 2 + 0, 0, 0);
                codeBlock(0);
                loadBlock8x8(i * 2 + 1, 0, 0);
                codeBlock(0);
                loadBlock16x8x8(i, 1);
                codeBlock(1);
                loadBlock16x8x8(i, 2);
                codeBlock(2);
            }
        }
        else
        {
            foreach (i; 0 .. mcusPerRow_)
            {
                loadBlock8x8(i * 2 + 0, 0, 0);
                codeBlock(0);
                loadBlock8x8(i * 2 + 1, 0, 0);
                codeBlock(0);
                loadBlock8x8(i * 2 + 0, 1, 0);
                codeBlock(0);
                loadBlock8x8(i * 2 + 1, 1, 0);
                codeBlock(0);
                loadBlock16x8(i, 1);
                codeBlock(1);
                loadBlock16x8(i, 2);
                codeBlock(2);
            }
        }
    }
}

// ---------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------

/// Encodes an image to `write`. `pixels` holds `height` lines of exactly
/// `width * channels` bytes each (`channels` is 1: Y, 3: RGB or 4: RGBA;
/// alpha is not stored in the JPEG). Throws `JpegException` if the
/// arguments are out of range.
void compressJpegToStream(JpegWriteFunc write, int width, int height, int channels,
    const(ubyte)[] pixels, JpegParams params = JpegParams.init)
{
    auto encoder = new JpegEncoder(write, width, height, channels, params);
    immutable size_t pitch = cast(size_t) width * channels;
    if (pixels.length < pitch * height)
        throw new JpegException(JpegStatus.badArguments);

    foreach (pass; 0 .. encoder.totalPasses)
    {
        foreach (y; 0 .. height)
            encoder.processScanline(pixels[y * pitch .. (y + 1) * pitch]);
        encoder.endPass();
    }
}

/// ditto, returning the JPEG file's content.
ubyte[] compressJpegToMemory(int width, int height, int channels,
    const(ubyte)[] pixels, JpegParams params = JpegParams.init)
{
    ubyte[] result;
    compressJpegToStream((const(ubyte)[] data) { result ~= data; }, width, height, channels, pixels, params);
    return result;
}

/// ditto, writing a JPEG file. Throws if the file cannot be written.
void compressJpegToFile(string filename, int width, int height, int channels,
    const(ubyte)[] pixels, JpegParams params = JpegParams.init)
{
    auto file = File(filename, "wb");
    compressJpegToStream((const(ubyte)[] data) { file.rawWrite(data); }, width, height, channels, pixels, params);
    file.close();
}

// ---------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------

version (unittest)
{
    import fl.jpeg_decoder : decompressJpegFromMemory, detectJpegFromMemory;

    /// A smooth RGB test image.
    private ubyte[] gradient(int w, int h)
    {
        auto pixels = new ubyte[](w * h * 3);
        foreach (y; 0 .. h)
            foreach (x; 0 .. w)
            {
                immutable size_t off = (cast(size_t) y * w + x) * 3;
                pixels[off] = cast(ubyte)(x * 255 / w);
                pixels[off + 1] = cast(ubyte)(y * 255 / h);
                pixels[off + 2] = cast(ubyte)((x + y) * 255 / (w + h));
            }
        return pixels;
    }

    private double meanAbsDiff(const(ubyte)[] a, const(ubyte)[] b)
    {
        assert(a.length == b.length);
        long sum;
        foreach (i; 0 .. a.length)
            sum += a[i] > b[i] ? a[i] - b[i] : b[i] - a[i];
        return cast(double) sum / a.length;
    }
}

unittest
{
    // Every subsampling and both Huffman modes round-trip, at sizes that
    // are and are not a multiple of the MCU.
    foreach (size; [[16, 16], [37, 29], [1, 1], [9, 17], [64, 8]])
    foreach (sub; [JpegSubsampling.h1v1, JpegSubsampling.h2v1, JpegSubsampling.h2v2])
    foreach (twoPass; [false, true])
    {
        immutable w = size[0], h = size[1];
        auto pixels = gradient(w, h);

        JpegParams params;
        params.subsampling = sub;
        params.twoPass = twoPass;
        params.quality = 95;
        auto jpeg = compressJpegToMemory(w, h, 3, pixels, params);

        int dw, dh, dc;
        assert(detectJpegFromMemory(jpeg, dw, dh, dc));
        assert(dw == w && dh == h && dc == 3);

        auto back = decompressJpegFromMemory(jpeg, dw, dh, dc, 3);
        assert(back.length == pixels.length);
        assert(meanAbsDiff(pixels, back) < 10.0);
    }
}

unittest
{
    // Grayscale, from 1, 3 and 4 channels of input.
    enum w = 24, h = 20;
    auto gray = new ubyte[](w * h);
    foreach (i; 0 .. gray.length)
        gray[i] = cast(ubyte)(i * 255 / gray.length);

    JpegParams params;
    params.subsampling = JpegSubsampling.yOnly;
    params.quality = 95;

    auto jpeg = compressJpegToMemory(w, h, 1, gray, params);
    int dw, dh, dc;
    auto back = decompressJpegFromMemory(jpeg, dw, dh, dc, 1);
    assert(dc == 1 && back.length == gray.length);
    assert(meanAbsDiff(gray, back) < 4.0);

    // RGB and RGBA input of the same gray image give the same file.
    auto rgb = new ubyte[](w * h * 3);
    auto rgba = new ubyte[](w * h * 4);
    foreach (i; 0 .. gray.length)
    {
        rgb[i * 3 .. i * 3 + 3] = gray[i];
        rgba[i * 4 .. i * 4 + 3] = gray[i];
        rgba[i * 4 + 3] = 17;
    }
    assert(compressJpegToMemory(w, h, 3, rgb, params) == compressJpegToMemory(w, h, 4, rgba, params));
}

unittest
{
    // A lower quality makes a smaller file; optimized tables make it
    // no larger than the standard ones.
    auto pixels = gradient(64, 48);
    JpegParams low, high, std;
    low.quality = 20;
    high.quality = 90;
    std.quality = 90;
    std.twoPass = false;
    assert(compressJpegToMemory(64, 48, 3, pixels, low).length < compressJpegToMemory(64, 48, 3, pixels, high).length);
    assert(compressJpegToMemory(64, 48, 3, pixels, high).length <= compressJpegToMemory(64, 48, 3, pixels, std).length);
}

unittest
{
    // The output reaches the write delegate in order and in full.
    auto pixels = gradient(100, 80);
    ubyte[] collected;
    compressJpegToStream((const(ubyte)[] data) { collected ~= data; }, 100, 80, 3, pixels);
    assert(collected == compressJpegToMemory(100, 80, 3, pixels));
    assert(collected[0 .. 2] == [0xFF, 0xD8] && collected[$ - 2 .. $] == [0xFF, 0xD9]);
}

unittest
{
    // Bad arguments.
    auto pixels = new ubyte[](12);
    void expectBad(void delegate() dg)
    {
        bool threw;
        try
            dg();
        catch (JpegException e)
            threw = e.status == JpegStatus.badArguments;
        assert(threw);
    }
    expectBad({ compressJpegToMemory(0, 2, 3, pixels); });
    expectBad({ compressJpegToMemory(2, 2, 2, pixels); }); // 2 channels
    expectBad({ compressJpegToMemory(2, 2, 3, pixels[0 .. 5]); }); // too few pixels
    JpegParams p;
    p.quality = 0;
    expectBad({ compressJpegToMemory(2, 2, 3, pixels, p); });
    p = JpegParams.init;
    p.subsampling = cast(JpegSubsampling) 7;
    expectBad({ compressJpegToMemory(2, 2, 3, pixels, p); });
}

unittest
{
    // Encoder and decoder output must stay identical to the jpge/jpgd
    // originals: SHA-1 of the encoded file and of its decoded RGB pixels,
    // for a 61x45 gradient at quality 80, as produced by those libraries.
    import std.digest.sha : sha1Of, toHexString;

    static immutable struct Golden { JpegSubsampling subsampling; bool twoPass; string encoded, decoded; }
    static immutable Golden[] golden = [
        Golden(JpegSubsampling.yOnly, true, "8E73FA495B9B672E8112159CC3224255E6EB3D9C", "CF1CD4D5B98BCAFFD4FE783EB639EF1C568BD051"),
        Golden(JpegSubsampling.yOnly, false, "494DBD5DAC9A5A6715A64B65A3D5AB008B54376E", "CF1CD4D5B98BCAFFD4FE783EB639EF1C568BD051"),
        Golden(JpegSubsampling.h1v1, true, "58D7D80042208E1F17700BC26D1EBB69B43613CE", "5C3BAA683E08DBBE0A02D62EB54C3A7779E5E608"),
        Golden(JpegSubsampling.h1v1, false, "C86A5CBC341CB9D4CC3431EA45307182864ECD47", "5C3BAA683E08DBBE0A02D62EB54C3A7779E5E608"),
        Golden(JpegSubsampling.h2v1, true, "709186B65F6A98CDDAAE7DA1A42DC01BF872BE4B", "63FC4904920E0312A051350E24C72D43545DE294"),
        Golden(JpegSubsampling.h2v1, false, "46CFE25C76AD052AE274DFA99223217FDBFD58E2", "63FC4904920E0312A051350E24C72D43545DE294"),
        Golden(JpegSubsampling.h2v2, true, "4B5B9C20C61C46C6B838BA41752A8B69CF82B1F1", "E2237372FA15303F6D2153802C3248D2AFA05120"),
        Golden(JpegSubsampling.h2v2, false, "8BEF07F4B326A85B4BCCC109342FA4FF110AECF8", "E2237372FA15303F6D2153802C3248D2AFA05120"),
    ];

    enum w = 61, h = 45;
    auto pixels = gradient(w, h);
    foreach (g; golden)
    {
        JpegParams params;
        params.quality = 80;
        params.subsampling = g.subsampling;
        params.twoPass = g.twoPass;

        auto jpeg = compressJpegToMemory(w, h, 3, pixels, params);
        assert(toHexString(sha1Of(jpeg)) == g.encoded);

        int dw, dh, dc;
        auto back = decompressJpegFromMemory(jpeg, dw, dh, dc, 3);
        assert(toHexString(sha1Of(back)) == g.decoded);
    }
}
