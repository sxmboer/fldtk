/*
 * Definitions shared by `fl.jpeg_decoder` and `fl.jpeg_encoder`: the JPEG
 * marker codes, the zig-zag scan order, the error type, and the
 * fixed-point constants of the integer DCT both directions use.
 *
 * `fl.jpeg_decoder` and `fl.jpeg_encoder` are D implementations of Rich
 * Geldreich's public-domain (Unlicense) jpgd (decoder) and jpge (encoder),
 * following the structure of Ketmar's D translation in Adam D. Ruppe's
 * `arsd` collection (`arsd/jpeg.d`). Both produce exactly the same output
 * as those libraries: the same integer IDCT/FDCT, the same Huffman
 * decoding, the same frequency-domain 2x chroma upsampling, the same
 * optimized Huffman tables.
 */
module fl.jpeg_common;

/// Reasons a JPEG stream is rejected, or an encode/decode request fails.
enum JpegStatus
{
    badDhtCounts,
    badDhtIndex,
    badDhtMarker,
    badDqtMarker,
    badDqtTable,
    badPrecision,
    badHeight,
    badWidth,
    tooManyComponents,
    badSofLength,
    badVariableMarker,
    badDriLength,
    badSosLength,
    badSosCompId,
    noArithmeticSupport,
    unexpectedMarker,
    notJpeg,
    unsupportedMarker,
    badDqtLength,
    undefinedQuantTable,
    undefinedHuffTable,
    unsupportedColorspace,
    unsupportedSampFactors,
    decodeError,
    badRestartMarker,
    badSosSpectral,
    badSosSuccessive,
    badArguments,
}

/// Thrown by the JPEG decoder and encoder; `status` says what was wrong.
class JpegException : Exception
{
    JpegStatus status;

    this(JpegStatus status, string file = __FILE__, size_t line = __LINE__)
    {
        import std.conv : to;
        super("JPEG error: " ~ status.to!string, file, line);
        this.status = status;
    }
}

/// JPEG marker codes (the byte following `0xFF`).
enum JpegMarker : int
{
    sof0 = 0xC0,
    sof1 = 0xC1,
    sof2 = 0xC2,
    sof3 = 0xC3,
    dht = 0xC4,
    sof5 = 0xC5,
    sof6 = 0xC6,
    sof7 = 0xC7,
    jpg = 0xC8,
    sof9 = 0xC9,
    sof10 = 0xCA,
    sof11 = 0xCB,
    dac = 0xCC,
    sof13 = 0xCD,
    sof14 = 0xCE,
    sof15 = 0xCF,
    rst0 = 0xD0,
    rst7 = 0xD7,
    soi = 0xD8,
    eoi = 0xD9,
    sos = 0xDA,
    dqt = 0xDB,
    dri = 0xDD,
    app0 = 0xE0,
    tem = 0x01,
}

/// Zig-zag order: `zigzag[i]` is the natural (row-major) position of the
/// i-th coefficient of a block as it appears in the stream.
static immutable ubyte[64] zigzag = [
     0,  1,  8, 16,  9,  2,  3, 10,
    17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
];

/// Fixed-point scale of the DCT constants (`FIX(x) == x * 2^13`).
enum constBits = 13;

/// Clamps `i` to 0..255.
ubyte clampByte(int i) pure nothrow @safe @nogc
{
    return cast(ubyte)(cast(uint) i > 255 ? ((~i) >> 31) & 0xFF : i);
}
