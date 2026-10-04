/*
 * JPEG decoder: baseline and progressive sequential-DCT JPEG (8-bit,
 * Huffman-coded) with 1 (grayscale) or 3 (YCbCr) components and the chroma
 * subsampling factors H1V1, H2V1, H1V2 and H2V2 (a grayscale image may also
 * carry 2x2 or 2x1 sampling factors). Arithmetic coding, 12-bit samples and
 * CMYK are not supported and are reported as a `JpegException`.
 *
 * This is a D implementation of Rich Geldreich's public-domain (Unlicense)
 * jpgd, following Ketmar's D translation in Adam D. Ruppe's `arsd`
 * collection (`arsd/jpeg.d`), and it produces the same pixels as that
 * decoder: the same fixed-point IDCT, and H2V2 chroma is upsampled in the
 * frequency domain (a 4x4 IDCT of an upsampled 8x8 coefficient block) rather
 * than by sample replication.
 *
 * The decoder reads from a `JpegReadFunc` delegate through its own input
 * buffer, so one implementation serves memory, file and stream sources;
 * `decompressJpegFromMemory()` and friends are the usual entry points.
 * Decoded images are always handed out as a whole `ubyte[]`; for line-wise
 * access use `JpegDecoder` directly.
 *
 * Failures are reported by throwing `JpegException` (see `fl.jpeg_common`),
 * never by crashing on a damaged stream: every table index and block
 * coordinate taken from the file is validated first.
 */
module fl.jpeg_decoder;

import fl.jpeg_common;
import std.stdio : File;

/// Input source for the decoder. Fills up to `buffer.length` bytes of
/// `buffer` and returns how many it wrote (which may be 0); sets
/// `endOfStream` when no more data will follow. It is called repeatedly
/// until the stream ends or the decoder's internal buffer is full. It may
/// throw to report a read error.
alias JpegReadFunc = size_t delegate(ubyte[] buffer, out bool endOfStream);

private enum inBufSize = 8192;
private enum inBufHeadroom = 16; // room in front of the data for stuffChar()
private enum maxHuffTables = 8; // 4 DC followed by 4 AC
private enum maxQuantTables = 4;
private enum maxComponents = 4;
private enum maxCompsInScan = 4;
private enum maxBlocksPerMcu = 10;
private enum maxBlocksPerRow = 8192;
private enum maxHeight = 16384;
private enum maxWidth = 16384;

private enum ScanType { grayscale, yh1v1, yh2v1, yh1v2, yh2v2 }

// ---------------------------------------------------------------------
// Inverse DCT (derived from the IJG jidctint algorithm)
// ---------------------------------------------------------------------

private enum pass1Bits = 2;

private enum fix_0_298631336 = 2446;
private enum fix_0_390180644 = 3196;
private enum fix_0_541196100 = 4433;
private enum fix_0_765366865 = 6270;
private enum fix_0_899976223 = 7373;
private enum fix_1_175875602 = 9633;
private enum fix_1_501321110 = 12299;
private enum fix_1_847759065 = 15137;
private enum fix_1_961570560 = 16069;
private enum fix_2_053119869 = 16819;
private enum fix_2_562915447 = 20995;
private enum fix_3_072711026 = 25172;

private int descale(int x, int n) pure nothrow @safe @nogc
{
    return (x + (1 << (n - 1))) >> n;
}

private int descaleZeroShift(int x, int n) pure nothrow @safe @nogc
{
    return (x + (128 << n) + (1 << (n - 1))) >> n;
}

/// One 8-point inverse DCT butterfly, shared by the row and the column
/// pass. Only the first `n` inputs may be nonzero; the code for each `n` is
/// generated separately, so the multiplications by the zero inputs vanish.
/// `o` receives the eight outputs, still scaled by 2^constBits.
private void idct1d(int n)(ref const int[8] s, ref int[8] o) pure nothrow @safe @nogc
{
    static assert(n >= 1 && n <= 8);

    immutable int s0 = s[0];
    static if (n > 1) immutable int s1 = s[1]; else enum int s1 = 0;
    static if (n > 2) immutable int s2 = s[2]; else enum int s2 = 0;
    static if (n > 3) immutable int s3 = s[3]; else enum int s3 = 0;
    static if (n > 4) immutable int s4 = s[4]; else enum int s4 = 0;
    static if (n > 5) immutable int s5 = s[5]; else enum int s5 = 0;
    static if (n > 6) immutable int s6 = s[6]; else enum int s6 = 0;
    static if (n > 7) immutable int s7 = s[7]; else enum int s7 = 0;

    immutable int z1 = (s2 + s6) * fix_0_541196100;
    immutable int tmp2 = z1 + s6 * (-fix_1_847759065);
    immutable int tmp3 = z1 + s2 * fix_0_765366865;

    immutable int tmp0 = (s0 + s4) << constBits;
    immutable int tmp1 = (s0 - s4) << constBits;

    immutable int tmp10 = tmp0 + tmp3, tmp13 = tmp0 - tmp3;
    immutable int tmp11 = tmp1 + tmp2, tmp12 = tmp1 - tmp2;

    // The odd part: s7, s5, s3, s1.
    immutable int bz1 = s7 + s1, bz2 = s5 + s3, bz3 = s7 + s3, bz4 = s5 + s1;
    immutable int bz5 = (bz3 + bz4) * fix_1_175875602;

    immutable int az1 = bz1 * (-fix_0_899976223);
    immutable int az2 = bz2 * (-fix_2_562915447);
    immutable int az3 = bz3 * (-fix_1_961570560) + bz5;
    immutable int az4 = bz4 * (-fix_0_390180644) + bz5;

    immutable int btmp0 = s7 * fix_0_298631336 + az1 + az3;
    immutable int btmp1 = s5 * fix_2_053119869 + az2 + az4;
    immutable int btmp2 = s3 * fix_3_072711026 + az2 + az3;
    immutable int btmp3 = s1 * fix_1_501321110 + az1 + az4;

    o[0] = tmp10 + btmp3;
    o[7] = tmp10 - btmp3;
    o[1] = tmp11 + btmp2;
    o[6] = tmp11 - btmp2;
    o[2] = tmp12 + btmp1;
    o[5] = tmp12 - btmp1;
    o[3] = tmp13 + btmp0;
    o[4] = tmp13 - btmp0;
}

/// Runs `idct1d` with the number of leading inputs that can be nonzero.
private void idct1dN(int n, ref const int[8] s, ref int[8] o) pure nothrow @safe @nogc
{
    switch (n)
    {
        static foreach (k; 1 .. 9)
        {
    case k:
            idct1d!k(s, o);
            return;
        }
    default:
        assert(false);
    }
}

/// The 64 coefficients of one block, in natural (row-major) order.
private alias CoefBlock = short[64];

/// The 64 samples of one decoded block, row-major.
private alias SampleBlock = ubyte[64];

/// Inverse DCT of one dequantized block into 64 samples (level-shifted and
/// clamped to 0..255).
///
/// Most coefficients of a typical block are zero, so each 1-D transform
/// is run only over the leading inputs that can be nonzero. The rows and
/// columns are unrolled so that every array index is a constant.
private void idctBlock(ref const CoefBlock src, ref SampleBlock dst) pure nothrow @safe @nogc
{
    int[8][8] tmp = void; // after the row pass
    int[8] s = void, o = void;

    // Row pass; `rows` ends up as the number of leading rows that are not
    // entirely zero (the others transform to zero).
    int rows = 0;
    static foreach (r; 0 .. 8)
    {
        {
            static foreach (k; 0 .. 8)
                s[k] = src[r * 8 + k];

            int n = 8;
            while (n > 0 && s[n - 1] == 0)
                n--;

            if (n == 0)
                tmp[r][] = 0;
            else
            {
                rows = r + 1;
                idct1dN(n, s, o);
                static foreach (k; 0 .. 8)
                    tmp[r][k] = descale(o[k], constBits - pass1Bits);
            }
        }
    }

    // Column pass.
    immutable int n = rows > 0 ? rows : 1;
    static foreach (c; 0 .. 8)
    {
        {
            static foreach (k; 0 .. 8)
                s[k] = k < n ? tmp[k][c] : 0;

            idct1dN(n, s, o);
            static foreach (k; 0 .. 8)
                dst[8 * k + c] = clampByte(descaleZeroShift(o[k], constBits + pass1Bits + 3));
        }
    }
}

// ---------------------------------------------------------------------
// Frequency-domain 2x upsampling of a chroma block (H2V2 images)
// ---------------------------------------------------------------------
//
// An 8x8 chroma coefficient block is turned into four 8x8 sample blocks,
// one per quadrant of the 16x16 area it covers, by splitting its
// coefficients into four 4x4 matrices (P, Q, R, S), recombining them
// (P+Q, P-Q, R+S, R-S) and running a 4x4 IDCT on each result. The mixing
// constants are the odd-part rows of the 8-point DCT scaled by 2^10 and
// truncated toward zero.

private enum upsampleFractBits = 10;

private immutable int[4] mixA = [426, 810, -360, 284]; // 0.415735 0.791065 -0.352443 0.277785
private immutable int[4] mixB = [23, -99, 502, 887]; // 0.022887 -0.097545 0.490393 0.865723
private immutable int[4] mixC = [928, -325, 218, -184]; // 0.906127 -0.318190 0.212608 -0.180240
private immutable int[4] mixE = [-75, 526, 787, -383]; // -0.074658 0.513280 0.768178 -0.375330

private alias Matrix44 = int[4][4]; // [row][column]

private int mix(const int[4] k, int x1, int x3, int x5, int x7) pure nothrow @safe @nogc
{
    return (k[0] * x1 + k[1] * x3 + k[2] * x5 + k[3] * x7 + (1 << (upsampleFractBits - 1))) >> upsampleFractBits;
}

/// Computes the 4x4 matrices of one half of the coefficient block: P and Q
/// from the even-numbered-column part (`first`), R and S from the other.
private void upsampleHalf(ref const CoefBlock src, bool first, ref Matrix44 p, ref Matrix44 q)
    pure nothrow @safe @nogc
{
    // Mix the columns of every row of the block.
    int[8][4] x = void;
    foreach (j; 0 .. 8)
    {
        const short[8] row = src[j * 8 .. j * 8 + 8];
        if (first)
        {
            x[0][j] = row[0];
            x[1][j] = mix(mixA, row[1], row[3], row[5], row[7]);
            x[2][j] = row[4];
            x[3][j] = mix(mixB, row[1], row[3], row[5], row[7]);
        }
        else
        {
            x[0][j] = mix(mixC, row[1], row[3], row[5], row[7]);
            x[1][j] = row[2];
            x[2][j] = mix(mixE, row[1], row[3], row[5], row[7]);
            x[3][j] = row[6];
        }
    }

    // Mix the rows.
    foreach (a; 0 .. 4)
    {
        p[a][0] = x[a][0];
        p[a][1] = mix(mixA, x[a][1], x[a][3], x[a][5], x[a][7]);
        p[a][2] = x[a][4];
        p[a][3] = mix(mixB, x[a][1], x[a][3], x[a][5], x[a][7]);

        q[a][0] = mix(mixC, x[a][1], x[a][3], x[a][5], x[a][7]);
        q[a][1] = x[a][2];
        q[a][2] = mix(mixE, x[a][1], x[a][3], x[a][5], x[a][7]);
        q[a][3] = x[a][6];
    }
}

/// Stores `a + sign*b` transposed into the top-left 4x4 corner of `block`.
private void storeSum(ref CoefBlock block, const ref Matrix44 a, const ref Matrix44 b, int sign)
    pure nothrow @safe @nogc
{
    foreach (r; 0 .. 4)
        foreach (c; 0 .. 4)
            block[c * 8 + r] = cast(short)(a[r][c] + sign * b[r][c]);
}

// ---------------------------------------------------------------------
// YCbCr -> RGB
// ---------------------------------------------------------------------

private struct YccTables
{
    int[256] crr, cbb, crg, cbg;
}

private YccTables makeYccTables() pure nothrow @safe @nogc
{
    // 1.40200, 1.77200, 0.71414 and 0.34414 as 16.16 fixed point.
    enum fixCrr = 91881, fixCbb = 116130, fixCrg = 46802, fixCbg = 22554;
    enum oneHalf = 1 << 15;

    YccTables t;
    foreach (i; 0 .. 256)
    {
        immutable int k = i - 128;
        t.crr[i] = (fixCrr * k + oneHalf) >> 16;
        t.cbb[i] = (fixCbb * k + oneHalf) >> 16;
        t.crg[i] = (-fixCrg) * k;
        t.cbg[i] = (-fixCbg) * k + oneHalf;
    }
    return t;
}

private immutable YccTables ycc = makeYccTables();

/// One pixel of a decoded color scan line.
private struct Rgba
{
    ubyte r, g, b, a;
}

/// Sets `px` to the opaque pixel for the given Y, Cb and Cr samples.
private void putRgba(ref Rgba px, int y, int cb, int cr) pure nothrow @safe @nogc
{
    px.r = clampByte(y + ycc.crr[cr]);
    px.g = clampByte(y + ((ycc.crg[cr] + ycc.cbg[cb]) >> 16));
    px.b = clampByte(y + ycc.cbb[cb]);
    px.a = 255;
}

// ---------------------------------------------------------------------
// Huffman and coefficient storage
// ---------------------------------------------------------------------

private struct HuffTable
{
    bool defined;

    // As read from a DHT marker.
    ubyte[17] counts; // counts[l] = number of codes of length l
    ubyte[256] values;

    // Derived by build().
    int[256] lookUp; // first 8 bits -> symbol, or a negative tree node
    int[256] lookUp2; // like lookUp, but with the extra bits of short codes folded in
    ubyte[256] codeSize;
    int[512] tree;

    /// Creates the tables needed for efficient decoding.
    void build()
    {
        ubyte[257] huffSize;
        uint[257] huffCode;

        int p = 0;
        foreach (l; 1 .. 17)
            foreach (i; 1 .. counts[l] + 1)
                huffSize[p++] = cast(ubyte) l;
        huffSize[p] = 0;
        immutable int lastP = p;

        uint code = 0;
        int si = huffSize[0];
        p = 0;
        while (huffSize[p])
        {
            while (huffSize[p] == si)
            {
                huffCode[p++] = code;
                code++;
            }
            code <<= 1;
            si++;
        }

        lookUp[] = 0;
        lookUp2[] = 0;
        tree[] = 0;
        codeSize[] = 0;

        int nextFreeEntry = -1;

        // Allocates the next pair of tree nodes; rejects tables whose codes
        // would need more nodes than the tree has room for.
        int allocNode()
        {
            if (-nextFreeEntry >= tree.length)
                throw new JpegException(JpegStatus.badDhtCounts);
            immutable int n = nextFreeEntry;
            nextFreeEntry -= 2;
            return n;
        }

        // Index into `tree` for a node reference; rejects tables whose
        // codes would need more nodes than the tree has room for.
        size_t treeIndex(int entry)
        {
            immutable int idx = -entry - 1;
            if (idx < 0 || idx >= tree.length)
                throw new JpegException(JpegStatus.badDhtCounts);
            return idx;
        }

        for (p = 0; p < lastP; p++)
        {
            immutable int symbol = values[p];
            code = huffCode[p];
            immutable int size = huffSize[p];

            codeSize[symbol] = cast(ubyte) size;

            if (size <= 8)
            {
                code <<= (8 - size);
                if (code + (1 << (8 - size)) > 256) // more codes than the code space holds
                    throw new JpegException(JpegStatus.badDhtCounts);

                foreach (l; 0 .. 1 << (8 - size))
                {
                    lookUp[code] = symbol;

                    bool hasExtraBits = false;
                    int extraBits = 0;
                    immutable int numExtraBits = symbol & 15;

                    int bitsToFetch = size;
                    if (numExtraBits)
                    {
                        immutable int totalCodeSize = size + numExtraBits;
                        if (totalCodeSize <= 8)
                        {
                            hasExtraBits = true;
                            extraBits = ((1 << numExtraBits) - 1) & (code >> (8 - totalCodeSize));
                            bitsToFetch += numExtraBits;
                        }
                    }

                    if (!hasExtraBits)
                        lookUp2[code] = symbol | (bitsToFetch << 8);
                    else
                        lookUp2[code] = symbol | 0x8000 | (extraBits << 16) | (bitsToFetch << 8);

                    code++;
                }
            }
            else
            {
                immutable uint subtree = (code >> (size - 8)) & 0xFF;

                int currentEntry = lookUp[subtree];
                if (currentEntry == 0)
                {
                    currentEntry = allocNode();
                    lookUp[subtree] = currentEntry;
                    lookUp2[subtree] = currentEntry;
                }

                code <<= (16 - (size - 8));

                for (int l = size; l > 9; l--)
                {
                    if ((code & 0x8000) == 0)
                        currentEntry--;

                    immutable size_t idx = treeIndex(currentEntry);
                    if (tree[idx] == 0)
                    {
                        currentEntry = allocNode();
                        tree[idx] = currentEntry;
                    }
                    else
                        currentEntry = tree[idx];

                    code <<= 1;
                }

                if ((code & 0x8000) == 0)
                    currentEntry--;

                tree[treeIndex(currentEntry)] = symbol;
            }
        }
    }
}

/// The coefficients of one component, kept for the whole image
/// (progressive JPEGs only): a grid of blocks of type `T`.
private struct CoeffBuffer(T)
{
    T[] data;
    int numX, numY;

    this(int numX, int numY)
    {
        this.numX = numX;
        this.numY = numY;
        data = new T[](cast(size_t) numX * numY);
    }

    /// Block (`x`, `y`).
    ref T block(int x, int y)
    {
        if (x < 0 || y < 0 || x >= numX || y >= numY)
            throw new JpegException(JpegStatus.decodeError);
        return data[cast(size_t) y * numX + x];
    }
}

private struct Component
{
    int id; // identifier from the frame header
    int hSamp, vSamp; // sampling factors
    int quantSel; // quantization table selector
    int hBlocks, vBlocks; // size in blocks
    int dcTab, acTab; // Huffman table selectors of the current scan
}

// ---------------------------------------------------------------------
// The decoder
// ---------------------------------------------------------------------

/// Decodes a JPEG stream one scan line at a time.
///
/// Construct it (which reads the header: `width`, `height` and
/// `numComponents` are then known), call `beginDecoding()`, then
/// `decodeScanLine()` `height` times. Any problem throws `JpegException`.
final class JpegDecoder
{
    private
    {
        // ---- input ----
        JpegReadFunc readFunc_;
        ubyte[] inBuf_;
        size_t inPos_; // index of the next byte to deliver
        size_t inLeft_; // bytes left in inBuf_
        bool eof_;
        bool temFlag_; // alternates 0xFF/0xD9 padding after the end of the stream
        int bitsLeft_;
        uint bitBuf_;

        // ---- frame ----
        int imageX_, imageY_;
        bool progressive_;
        HuffTable[maxHuffTables] huff_;
        short[64][maxQuantTables] quant_; // in zig-zag order
        bool[maxQuantTables] quantDefined_;
        int numComps_;
        Component[maxComponents] comp_;
        ScanType scanType_;
        int maxMcuXSize_, maxMcuYSize_;
        int maxBlocksPerMcu_, maxBlocksPerRow_;
        int maxMcusPerRow_, maxMcusPerCol_;
        int restartInterval_;
        int destBytesPerScanLine_, realDestBytesPerScanLine_, destBytesPerPixel_;
        bool freqDomainChromaUpsample_;
        int expandedBlocksPerMcu_, expandedBlocksPerComponent_, expandedBlocksPerRow_;

        // ---- scan ----
        int scanComps_;
        int[maxCompsInScan] compList_;
        int spectralStart_, spectralEnd_, successiveLow_, successiveHigh_;
        int mcusPerRow_, mcusPerCol_;
        int blocksPerMcu_;
        int[maxBlocksPerMcu] mcuOrg_;
        int restartsLeft_, nextRestartNum_;
        int eobRun_;
        uint[maxComponents] lastDcVal_;
        int[maxComponents] blockYMcu_; // progressive row decoding
        CoeffBuffer!short[maxComponents] dcCoeffs_;
        CoeffBuffer!CoefBlock[maxComponents] acCoeffs_;

        // ---- output ----
        CoefBlock[] mcuCoefs_; // one MCU of dequantized coefficients
        SampleBlock[] sampleBuf_; // one MCU row of samples
        ubyte[] grayLine_; // the scan line of a grayscale image
        Rgba[] colorLine0_, colorLine1_; // the scan line(s) of a color image
        int totalLinesLeft_, mcuLinesLeft_;
        bool ready_;
    }

    /// Reads the JPEG header from `read`. Throws if it is not a JPEG
    /// stream this decoder can handle.
    this(JpegReadFunc read)
    {
        if (read is null)
            throw new JpegException(JpegStatus.badArguments);
        readFunc_ = read;
        inBuf_ = new ubyte[](inBufHeadroom + inBufSize);

        inPos_ = inBufHeadroom;
        prepInBuffer();

        // Prime the bit buffer.
        bitsLeft_ = 16;
        bitBuf_ = 0;
        getBits(16);
        getBits(16);

        locateSofMarker();
    }

    /// Width of the image in pixels.
    int width() const pure nothrow @safe @nogc { return imageX_; }

    /// Height of the image in pixels.
    int height() const pure nothrow @safe @nogc { return imageY_; }

    /// Number of components in the image: 1 (grayscale) or 3 (color).
    int numComponents() const pure nothrow @safe @nogc { return numComps_; }

    /// Bytes per pixel of the scan lines `decodeScanLine()` returns: 1 for
    /// grayscale, 4 (RGBA, alpha always 255) for color.
    int bytesPerPixel() const pure nothrow @safe @nogc { return destBytesPerPixel_; }

    /// Starts decompression. Call it once before `decodeScanLine()`.
    void beginDecoding()
    {
        if (ready_)
            return;
        decodeStart();
        ready_ = true;
    }

    /// Returns the next scan line: `width * bytesPerPixel` bytes. The slice
    /// is only valid until the next call.
    const(ubyte)[] decodeScanLine()
    {
        if (!ready_ || totalLinesLeft_ == 0)
            throw new JpegException(JpegStatus.decodeError);

        const(ubyte)[] line;
        if (mcuLinesLeft_ == 0)
        {
            if (progressive_)
                loadNextRow();
            else
                decodeNextRow();
            // Find the EOI marker if that was the last row.
            if (totalLinesLeft_ <= maxMcuYSize_)
                findEoi();
            mcuLinesLeft_ = maxMcuYSize_;
        }

        if (scanType_ == ScanType.grayscale)
        {
            convertGray();
            line = grayLine_;
        }
        else if (freqDomainChromaUpsample_)
        {
            expandedConvert();
            line = cast(const(ubyte)[]) colorLine0_;
        }
        else if (scanType_ == ScanType.yh2v1)
        {
            convertH2V1();
            line = cast(const(ubyte)[]) colorLine0_;
        }
        else if (scanType_ == ScanType.yh1v2)
        {
            // One MCU row yields two scan lines at once.
            if ((mcuLinesLeft_ & 1) == 0)
            {
                convertH1V2();
                line = cast(const(ubyte)[]) colorLine0_;
            }
            else
                line = cast(const(ubyte)[]) colorLine1_;
        }
        else
        {
            convertH1V1();
            line = cast(const(ubyte)[]) colorLine0_;
        }

        --mcuLinesLeft_;
        --totalLinesLeft_;
        return line[0 .. realDestBytesPerScanLine_];
    }

private:
    // -----------------------------------------------------------------
    // Input
    // -----------------------------------------------------------------

    /// Refills the input buffer, looping until it is full or the stream ends.
    void prepInBuffer()
    {
        inLeft_ = 0;
        inPos_ = inBufHeadroom;

        if (eof_)
            return;

        do
        {
            bool endOfStream;
            immutable size_t n = readFunc_(inBuf_[inBufHeadroom + inLeft_ .. $], endOfStream);
            if (n > inBufSize - inLeft_)
                throw new JpegException(JpegStatus.decodeError);
            inLeft_ += n;
            eof_ = endOfStream;
        }
        while (inLeft_ < inBufSize && !eof_);
    }

    /// Retrieves one byte. Past the end of the stream the stream is padded
    /// with the endless sequence 0xFF 0xD9 (an EOI marker).
    uint getChar()
    {
        bool padding;
        return getChar(padding);
    }

    /// Same, but also says whether the byte is padding.
    uint getChar(out bool padding)
    {
        if (inLeft_ == 0)
        {
            prepInBuffer();
            if (inLeft_ == 0)
            {
                padding = true;
                immutable bool t = temFlag_;
                temFlag_ = !temFlag_;
                return t ? 0xD9 : 0xFF;
            }
        }
        padding = false;
        --inLeft_;
        return inBuf_[inPos_++];
    }

    /// Pushes a previously retrieved byte back.
    void stuffChar(ubyte q)
    {
        inBuf_[--inPos_] = q;
        inLeft_++;
    }

    /// Retrieves one byte, but does not read past markers: a marker is
    /// reported as an endless run of 0xFF.
    ubyte getOctet()
    {
        bool padding;
        int c = getChar(padding);
        if (c == 0xFF)
        {
            if (padding)
                return 0xFF;
            c = getChar(padding);
            if (padding)
            {
                stuffChar(0xFF);
                return 0xFF;
            }
            if (c == 0x00)
                return 0xFF;
            stuffChar(cast(ubyte) c);
            stuffChar(0xFF);
            return 0xFF;
        }
        return cast(ubyte) c;
    }

    /// Retrieves `numBits` bits. Does not recognize markers.
    uint getBits(int numBits)
    {
        if (!numBits)
            return 0;
        immutable uint i = bitBuf_ >> (32 - numBits);
        if ((bitsLeft_ -= numBits) <= 0)
        {
            bitBuf_ <<= (numBits += bitsLeft_);
            immutable uint c1 = getChar();
            immutable uint c2 = getChar();
            bitBuf_ = (bitBuf_ & 0xFFFF0000) | (c1 << 8) | c2;
            bitBuf_ <<= -bitsLeft_;
            bitsLeft_ += 16;
        }
        else
            bitBuf_ <<= numBits;
        return i;
    }

    /// Retrieves `numBits` bits; markers are not read into the bit buffer,
    /// an endless run of 1 bits is returned instead.
    uint getBitsNoMarkers(int numBits)
    {
        if (!numBits)
            return 0;
        immutable uint i = bitBuf_ >> (32 - numBits);
        if ((bitsLeft_ -= numBits) <= 0)
        {
            bitBuf_ <<= (numBits += bitsLeft_);
            if (inLeft_ < 2 || inBuf_[inPos_] == 0xFF || inBuf_[inPos_ + 1] == 0xFF)
            {
                immutable uint c1 = getOctet();
                immutable uint c2 = getOctet();
                bitBuf_ |= (c1 << 8) | c2;
            }
            else
            {
                bitBuf_ |= (cast(uint) inBuf_[inPos_] << 8) | inBuf_[inPos_ + 1];
                inLeft_ -= 2;
                inPos_ += 2;
            }
            bitBuf_ <<= -bitsLeft_;
            bitsLeft_ += 16;
        }
        else
            bitBuf_ <<= numBits;
        return i;
    }

    // -----------------------------------------------------------------
    // Huffman decoding
    // -----------------------------------------------------------------

    /// Decodes one Huffman-coded symbol.
    int huffDecode(ref const HuffTable h)
    {
        int symbol = h.lookUp[bitBuf_ >> 24];
        // Check the first 8 bits: do we have a complete symbol?
        if (symbol < 0)
        {
            // Decode more bits, using a tree traversal.
            int ofs = 23;
            do
            {
                if (ofs < 16) // codes are at most 16 bits long
                    throw new JpegException(JpegStatus.decodeError);
                symbol = h.tree[-cast(int)(symbol + ((bitBuf_ >> ofs) & 1))];
                --ofs;
            }
            while (symbol < 0);
            getBitsNoMarkers(8 + (23 - ofs));
        }
        else
            getBitsNoMarkers(h.codeSize[symbol]);
        return symbol;
    }

    /// Decodes one symbol together with its extra bits (the magnitude bits
    /// of a coefficient), returned in `extraBits`.
    int huffDecode(ref const HuffTable h, out int extraBits)
    {
        int symbol = h.lookUp2[bitBuf_ >> 24];
        if (symbol < 0)
        {
            int ofs = 23;
            do
            {
                if (ofs < 16) // codes are at most 16 bits long
                    throw new JpegException(JpegStatus.decodeError);
                symbol = h.tree[-cast(int)(symbol + ((bitBuf_ >> ofs) & 1))];
                --ofs;
            }
            while (symbol < 0);
            getBitsNoMarkers(8 + (23 - ofs));
            extraBits = getBitsNoMarkers(symbol & 0xF);
        }
        else
        {
            if (symbol & 0x8000)
            {
                getBitsNoMarkers((symbol >> 8) & 31);
                extraBits = symbol >> 16;
            }
            else
            {
                immutable int codeSize = (symbol >> 8) & 31;
                immutable int numExtraBits = symbol & 0xF;
                immutable int bits = codeSize + numExtraBits;
                if (bits <= (bitsLeft_ + 16))
                    extraBits = getBitsNoMarkers(bits) & ((1 << numExtraBits) - 1);
                else
                {
                    getBitsNoMarkers(codeSize);
                    extraBits = getBitsNoMarkers(numExtraBits);
                }
            }
            symbol &= 0xFF;
        }
        return symbol;
    }

    /// Sign-extends a coefficient read as `s` magnitude bits.
    static int huffExtend(int x, int s) pure nothrow @safe @nogc
    {
        // (-1 << s) + 1 for s in 1..15; the table form avoids a shift by 0.
        static immutable int[16] extendTest = [
            0, 0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020, 0x0040,
            0x0080, 0x0100, 0x0200, 0x0400, 0x0800, 0x1000, 0x2000, 0x4000,
        ];
        immutable int t = s & 15;
        if (x < extendTest[t])
            return x + (t == 0 ? 0 : ((-1) << t) + 1);
        return x;
    }

    // -----------------------------------------------------------------
    // Markers
    // -----------------------------------------------------------------

    /// Reads a Huffman table definition (DHT).
    void readDhtMarker()
    {
        uint numLeft = getBits(16);
        if (numLeft < 2)
            throw new JpegException(JpegStatus.badDhtMarker);
        numLeft -= 2;

        while (numLeft)
        {
            int index = getBits(8);

            ubyte[17] counts;
            ubyte[256] values;
            int count = 0;
            foreach (i; 1 .. 17)
            {
                counts[i] = cast(ubyte) getBits(8);
                count += counts[i];
            }

            if (count > 255)
                throw new JpegException(JpegStatus.badDhtCounts);

            foreach (i; 0 .. count)
                values[i] = cast(ubyte) getBits(8);

            immutable uint used = 1 + 16 + count;
            if (numLeft < used)
                throw new JpegException(JpegStatus.badDhtMarker);
            numLeft -= used;

            // DC tables 0-3 are stored first, AC tables 0-3 after them.
            index = (index & 0x0F) + ((index & 0x10) >> 4) * (maxHuffTables >> 1);
            if (index >= maxHuffTables)
                throw new JpegException(JpegStatus.badDhtIndex);

            huff_[index].defined = true;
            huff_[index].counts = counts;
            huff_[index].values = values;
        }
    }

    /// Reads a quantization table definition (DQT).
    void readDqtMarker()
    {
        uint numLeft = getBits(16);
        if (numLeft < 2)
            throw new JpegException(JpegStatus.badDqtMarker);
        numLeft -= 2;

        while (numLeft)
        {
            int n = getBits(8);
            immutable int precision = n >> 4;
            n &= 0x0F;

            if (n >= maxQuantTables)
                throw new JpegException(JpegStatus.badDqtTable);

            // The entries are in zig-zag order.
            foreach (i; 0 .. 64)
            {
                uint temp = getBits(8);
                if (precision)
                    temp = (temp << 8) + getBits(8);
                quant_[n][i] = cast(short) temp;
            }
            quantDefined_[n] = true;

            immutable uint used = 64 + 1 + (precision ? 64 : 0);
            if (numLeft < used)
                throw new JpegException(JpegStatus.badDqtLength);
            numLeft -= used;
        }
    }

    /// Reads the start-of-frame marker (SOF).
    void readSofMarker()
    {
        immutable uint numLeft = getBits(16);

        if (getBits(8) != 8) // only 8-bit precision is supported
            throw new JpegException(JpegStatus.badPrecision);

        imageY_ = getBits(16);
        if (imageY_ < 1 || imageY_ > maxHeight)
            throw new JpegException(JpegStatus.badHeight);

        imageX_ = getBits(16);
        if (imageX_ < 1 || imageX_ > maxWidth)
            throw new JpegException(JpegStatus.badWidth);

        numComps_ = getBits(8);
        if (numComps_ > maxComponents)
            throw new JpegException(JpegStatus.tooManyComponents);

        if (numLeft != cast(uint)(numComps_ * 3 + 8))
            throw new JpegException(JpegStatus.badSofLength);

        foreach (i; 0 .. numComps_)
        {
            comp_[i].id = getBits(8);
            comp_[i].hSamp = getBits(4);
            comp_[i].vSamp = getBits(4);
            comp_[i].quantSel = getBits(8);
            if (comp_[i].quantSel >= maxQuantTables)
                throw new JpegException(JpegStatus.badDqtTable);
        }
    }

    /// Skips a marker segment whose content is not needed.
    void skipVariableMarker()
    {
        uint numLeft = getBits(16);
        if (numLeft < 2)
            throw new JpegException(JpegStatus.badVariableMarker);
        numLeft -= 2;
        while (numLeft)
        {
            getBits(8);
            numLeft--;
        }
    }

    /// Reads a define-restart-interval marker (DRI).
    void readDriMarker()
    {
        if (getBits(16) != 4)
            throw new JpegException(JpegStatus.badDriLength);
        restartInterval_ = getBits(16);
    }

    /// Reads a start-of-scan marker (SOS).
    void readSosMarker()
    {
        uint numLeft = getBits(16);
        immutable int n = getBits(8);
        scanComps_ = n;
        numLeft -= 3;

        if (numLeft != cast(uint)(n * 2 + 3) || n < 1 || n > maxCompsInScan)
            throw new JpegException(JpegStatus.badSosLength);

        foreach (i; 0 .. n)
        {
            immutable int cc = getBits(8);
            immutable int c = getBits(8);
            numLeft -= 2;

            int ci;
            for (ci = 0; ci < numComps_; ci++)
                if (cc == comp_[ci].id)
                    break;
            if (ci >= numComps_)
                throw new JpegException(JpegStatus.badSosCompId);

            // DC and AC tables are numbered 0-3 each.
            if (((c >> 4) & 15) >= (maxHuffTables >> 1) || (c & 15) >= (maxHuffTables >> 1))
                throw new JpegException(JpegStatus.badDhtIndex);

            compList_[i] = ci;
            comp_[ci].dcTab = (c >> 4) & 15;
            comp_[ci].acTab = (c & 15) + (maxHuffTables >> 1);
        }

        spectralStart_ = getBits(8);
        spectralEnd_ = getBits(8);
        successiveHigh_ = getBits(4);
        successiveLow_ = getBits(4);

        if (!progressive_)
        {
            spectralStart_ = 0;
            spectralEnd_ = 63;
        }

        numLeft -= 3;

        // Read past whatever is left.
        while (numLeft)
        {
            getBits(8);
            numLeft--;
        }
    }

    /// Finds the next marker and returns its code.
    int nextMarker()
    {
        uint c;
        do
        {
            do
            {
                c = getBits(8);
            }
            while (c != 0xFF);

            do
            {
                c = getBits(8);
            }
            while (c == 0xFF);
        }
        while (c == 0);

        return c;
    }

    /// Processes markers; returns when an SOFx, SOI, EOI or SOS marker is
    /// found. With `allowRestarts`, restart markers are skipped.
    int processMarkers(bool allowRestarts = false)
    {
        for (;;)
        {
            immutable int c = nextMarker();

            switch (c)
            {
            case JpegMarker.sof0, JpegMarker.sof1, JpegMarker.sof2, JpegMarker.sof3,
                JpegMarker.sof5, JpegMarker.sof6, JpegMarker.sof7,
                JpegMarker.sof9, JpegMarker.sof10, JpegMarker.sof11,
                JpegMarker.sof13, JpegMarker.sof14, JpegMarker.sof15,
                JpegMarker.soi, JpegMarker.eoi, JpegMarker.sos:
                return c;
            case JpegMarker.dht:
                readDhtMarker();
                break;
            case JpegMarker.dac: // arithmetic coding is not supported
                throw new JpegException(JpegStatus.noArithmeticSupport);
            case JpegMarker.dqt:
                readDqtMarker();
                break;
            case JpegMarker.dri:
                readDriMarker();
                break;
            case JpegMarker.rst0: .. case JpegMarker.rst7: // no parameters
                if (allowRestarts)
                    continue;
                throw new JpegException(JpegStatus.unexpectedMarker);
            case JpegMarker.jpg, JpegMarker.tem:
                throw new JpegException(JpegStatus.unexpectedMarker);
            default: // DNL, DHP, EXP, APPn, JPGn, COM, RESn
                skipVariableMarker();
                break;
            }
        }
    }

    /// Finds the start-of-image marker. Only the first 4096 bytes are
    /// searched, to avoid false positives.
    void locateSoiMarker()
    {
        uint lastChar = getBits(8);
        uint thisChar = getBits(8);

        // Fine if it is a normal JPEG file without a special header.
        if (lastChar == 0xFF && thisChar == JpegMarker.soi)
            return;

        uint bytesLeft = 4096;
        for (;;)
        {
            if (--bytesLeft == 0)
                throw new JpegException(JpegStatus.notJpeg);

            lastChar = thisChar;
            thisChar = getBits(8);

            if (lastChar == 0xFF)
            {
                if (thisChar == JpegMarker.soi)
                    break;
                else if (thisChar == JpegMarker.eoi) // getBits keeps returning EOI past the end
                    throw new JpegException(JpegStatus.notJpeg);
            }
        }

        // The byte after the marker must be the 0xFF that starts the next
        // marker; if not, the file is bad.
        if (((bitBuf_ >> 24) & 0xFF) != 0xFF)
            throw new JpegException(JpegStatus.notJpeg);
    }

    /// Finds the start-of-frame marker and reads it.
    void locateSofMarker()
    {
        locateSoiMarker();

        switch (processMarkers())
        {
        case JpegMarker.sof2:
            progressive_ = true;
            goto case;
        case JpegMarker.sof0: // baseline DCT
        case JpegMarker.sof1: // extended sequential DCT
            readSofMarker();
            break;
        case JpegMarker.sof9: // arithmetic coding
            throw new JpegException(JpegStatus.noArithmeticSupport);
        default:
            throw new JpegException(JpegStatus.unsupportedMarker);
        }
    }

    /// Finds the start-of-scan marker and reads it; false at end of image.
    bool locateSosMarker()
    {
        immutable int c = processMarkers();
        if (c == JpegMarker.eoi)
            return false;
        if (c != JpegMarker.sos)
            throw new JpegException(JpegStatus.unexpectedMarker);

        readSosMarker();
        return true;
    }

    // -----------------------------------------------------------------
    // Frame and scan setup
    // -----------------------------------------------------------------

    /// Returns to the stream any bytes that were read into the bit buffer
    /// during marker scanning.
    void fixInBuffer()
    {
        // In case any 0xFFs were pulled into the buffer during marker scanning.
        if (bitsLeft_ == 16)
            stuffChar(cast(ubyte)(bitBuf_ & 0xFF));

        if (bitsLeft_ >= 8)
            stuffChar(cast(ubyte)((bitBuf_ >> 8) & 0xFF));

        stuffChar(cast(ubyte)((bitBuf_ >> 16) & 0xFF));
        stuffChar(cast(ubyte)((bitBuf_ >> 24) & 0xFF));

        bitsLeft_ = 16;
        getBitsNoMarkers(16);
        getBitsNoMarkers(16);
    }

    /// Determines the component order inside each MCU, and how many MCUs
    /// are on each row.
    void calcMcuBlockOrder()
    {
        int maxHSamp = 0, maxVSamp = 0;
        foreach (ci; 0 .. numComps_)
        {
            if (comp_[ci].hSamp > maxHSamp)
                maxHSamp = comp_[ci].hSamp;
            if (comp_[ci].vSamp > maxVSamp)
                maxVSamp = comp_[ci].vSamp;
        }

        foreach (ci; 0 .. numComps_)
        {
            comp_[ci].hBlocks = ((((imageX_ * comp_[ci].hSamp) + (maxHSamp - 1)) / maxHSamp) + 7) / 8;
            comp_[ci].vBlocks = ((((imageY_ * comp_[ci].vSamp) + (maxVSamp - 1)) / maxVSamp) + 7) / 8;
        }

        if (scanComps_ == 1)
        {
            mcusPerRow_ = comp_[compList_[0]].hBlocks;
            mcusPerCol_ = comp_[compList_[0]].vBlocks;

            mcuOrg_[0] = compList_[0];
            blocksPerMcu_ = 1;
        }
        else
        {
            mcusPerRow_ = (((imageX_ + 7) / 8) + (maxHSamp - 1)) / maxHSamp;
            mcusPerCol_ = (((imageY_ + 7) / 8) + (maxVSamp - 1)) / maxVSamp;

            blocksPerMcu_ = 0;
            foreach (i; 0 .. scanComps_)
            {
                immutable int ci = compList_[i];
                foreach (b; 0 .. comp_[ci].hSamp * comp_[ci].vSamp)
                {
                    if (blocksPerMcu_ >= maxBlocksPerMcu)
                        throw new JpegException(JpegStatus.unsupportedSampFactors);
                    mcuOrg_[blocksPerMcu_++] = ci;
                }
            }
        }
    }

    /// Verifies the quantization tables needed for this scan are defined.
    void checkQuantTables()
    {
        foreach (i; 0 .. scanComps_)
            if (!quantDefined_[comp_[compList_[i]].quantSel])
                throw new JpegException(JpegStatus.undefinedQuantTable);
    }

    /// Verifies the Huffman tables needed for this scan are defined, and
    /// builds the decoding tables.
    void checkHuffTables()
    {
        foreach (i; 0 .. scanComps_)
        {
            immutable int ci = compList_[i];
            if (spectralStart_ == 0 && !huff_[comp_[ci].dcTab].defined)
                throw new JpegException(JpegStatus.undefinedHuffTable);
            if (spectralEnd_ > 0 && !huff_[comp_[ci].acTab].defined)
                throw new JpegException(JpegStatus.undefinedHuffTable);
        }

        foreach (ref h; huff_)
            if (h.defined)
                h.build();
    }

    /// Starts a new scan; false if there is none (end of image).
    bool initScan()
    {
        if (!locateSosMarker())
            return false;

        calcMcuBlockOrder();
        checkHuffTables();
        checkQuantTables();

        lastDcVal_[0 .. numComps_] = 0;
        eobRun_ = 0;

        if (restartInterval_)
        {
            restartsLeft_ = restartInterval_;
            nextRestartNum_ = 0;
        }

        fixInBuffer();
        return true;
    }

    /// Starts a frame: checks the component count and sampling factors
    /// and allocates the working buffers.
    void initFrame()
    {
        if (numComps_ == 1)
        {
            immutable int h = comp_[0].hSamp, v = comp_[0].vSamp;
            if (h == 1 && v == 1)
            {
                scanType_ = ScanType.grayscale;
                maxBlocksPerMcu_ = 1;
            }
            else if ((h == 2 && v == 2) || (h == 2 && v == 1))
            {
                // Grayscale images with these (meaningless) factors do occur.
                scanType_ = ScanType.grayscale;
                maxBlocksPerMcu_ = 4;
            }
            else
                throw new JpegException(JpegStatus.unsupportedSampFactors);
            maxMcuXSize_ = 8;
            maxMcuYSize_ = 8;
        }
        else if (numComps_ == 3)
        {
            if (comp_[1].hSamp != 1 || comp_[1].vSamp != 1 || comp_[2].hSamp != 1 || comp_[2].vSamp != 1)
                throw new JpegException(JpegStatus.unsupportedSampFactors);

            immutable int h = comp_[0].hSamp, v = comp_[0].vSamp;
            if (h == 1 && v == 1)
            {
                scanType_ = ScanType.yh1v1;
                maxBlocksPerMcu_ = 3;
                maxMcuXSize_ = 8;
                maxMcuYSize_ = 8;
            }
            else if (h == 2 && v == 1)
            {
                scanType_ = ScanType.yh2v1;
                maxBlocksPerMcu_ = 4;
                maxMcuXSize_ = 16;
                maxMcuYSize_ = 8;
            }
            else if (h == 1 && v == 2)
            {
                scanType_ = ScanType.yh1v2;
                maxBlocksPerMcu_ = 4;
                maxMcuXSize_ = 8;
                maxMcuYSize_ = 16;
            }
            else if (h == 2 && v == 2)
            {
                scanType_ = ScanType.yh2v2;
                maxBlocksPerMcu_ = 6;
                maxMcuXSize_ = 16;
                maxMcuYSize_ = 16;
            }
            else
                throw new JpegException(JpegStatus.unsupportedSampFactors);
        }
        else
            throw new JpegException(JpegStatus.unsupportedColorspace);

        maxMcusPerRow_ = (imageX_ + (maxMcuXSize_ - 1)) / maxMcuXSize_;
        maxMcusPerCol_ = (imageY_ + (maxMcuYSize_ - 1)) / maxMcuYSize_;

        // These values are for the destination pixels: after conversion.
        destBytesPerPixel_ = scanType_ == ScanType.grayscale ? 1 : 4;
        destBytesPerScanLine_ = ((imageX_ + 15) & 0xFFF0) * destBytesPerPixel_;
        realDestBytesPerScanLine_ = imageX_ * destBytesPerPixel_;

        // The scan line buffers (a vertically subsampled MCU yields two color lines at once).
        if (scanType_ == ScanType.grayscale)
            grayLine_ = new ubyte[](destBytesPerScanLine_);
        else
        {
            colorLine0_ = new Rgba[](destBytesPerScanLine_ / 4);
            if (scanType_ == ScanType.yh1v2)
                colorLine1_ = new Rgba[](destBytesPerScanLine_ / 4);
        }

        maxBlocksPerRow_ = maxMcusPerRow_ * maxBlocksPerMcu_;
        if (maxBlocksPerRow_ > maxBlocksPerRow)
            throw new JpegException(JpegStatus.decodeError);

        // The coefficients of one MCU.
        mcuCoefs_ = new CoefBlock[](maxBlocksPerMcu_);

        expandedBlocksPerComponent_ = comp_[0].hSamp * comp_[0].vSamp;
        expandedBlocksPerMcu_ = expandedBlocksPerComponent_ * numComps_;
        expandedBlocksPerRow_ = maxMcusPerRow_ * expandedBlocksPerMcu_;
        // Frequency-domain chroma upsampling is used for H2V2 color images.
        freqDomainChromaUpsample_ = expandedBlocksPerMcu_ == 4 * 3;

        sampleBuf_ = new SampleBlock[](freqDomainChromaUpsample_ ? expandedBlocksPerRow_ : maxBlocksPerRow_);

        totalLinesLeft_ = imageY_;
        mcuLinesLeft_ = 0;
    }

    void decodeStart()
    {
        initFrame();

        if (progressive_)
            initProgressive();
        else
            initSequential();
    }

    void initSequential()
    {
        if (!initScan())
            throw new JpegException(JpegStatus.unexpectedMarker);
    }

    // -----------------------------------------------------------------
    // Sequential decoding
    // -----------------------------------------------------------------

    /// Handles a restart interval boundary.
    void processRestart()
    {
        // Scan a little to find the marker, but not too far.
        int i;
        for (i = 1536; i > 0; i--)
            if (getChar() == 0xFF)
                break;
        if (i == 0)
            throw new JpegException(JpegStatus.badRestartMarker);

        uint c = 0;
        for (; i > 0; i--)
            if ((c = getChar()) != 0xFF)
                break;
        if (i == 0)
            throw new JpegException(JpegStatus.badRestartMarker);

        // Is it the expected marker? If not, something bad happened.
        if (c != cast(uint)(nextRestartNum_ + JpegMarker.rst0))
            throw new JpegException(JpegStatus.badRestartMarker);

        // Reset each component's DC prediction value.
        lastDcVal_[0 .. numComps_] = 0;
        eobRun_ = 0;
        restartsLeft_ = restartInterval_;
        nextRestartNum_ = (nextRestartNum_ + 1) & 7;

        // Get the bit buffer going again.
        bitsLeft_ = 16;
        getBitsNoMarkers(16);
        getBitsNoMarkers(16);
    }

    /// Decodes and dequantizes the next row of MCUs and converts it to samples.
    void decodeNextRow()
    {
        foreach (mcuRow; 0 .. mcusPerRow_)
        {
            if (restartInterval_ && restartsLeft_ == 0)
                processRestart();

            foreach (mcuBlock; 0 .. blocksPerMcu_)
            {
                ref CoefBlock p = mcuCoefs_[mcuBlock];
                p[] = 0;

                immutable int ci = mcuOrg_[mcuBlock];
                ref const short[64] q = quant_[comp_[ci].quantSel];

                // The DC coefficient is coded as a difference from the previous block.
                int r;
                int s = huffDecode(huff_[comp_[ci].dcTab], r);
                s = huffExtend(r, s);
                lastDcVal_[ci] = (s += lastDcVal_[ci]);
                p[0] = cast(short)(s * q[0]);

                ref const(HuffTable) ac = huff_[comp_[ci].acTab];

                int k;
                for (k = 1; k < 64; k++)
                {
                    int extraBits;
                    s = huffDecode(ac, extraBits);

                    r = s >> 4;
                    s &= 15;

                    if (s)
                    {
                        if (r)
                        {
                            if (k + r > 63)
                                throw new JpegException(JpegStatus.decodeError);
                            k += r;
                        }

                        s = huffExtend(extraBits, s);
                        p[zigzag[k]] = cast(short)(s * q[k]);
                    }
                    else
                    {
                        if (r == 15)
                        {
                            if (k + 16 > 64)
                                throw new JpegException(JpegStatus.decodeError);
                            k += 16 - 1; // - 1 because the loop counter is k
                        }
                        else
                            break;
                    }
                }
            }

            if (freqDomainChromaUpsample_)
                transformMcuExpand(mcuRow);
            else
                transformMcu(mcuRow);

            restartsLeft_--;
        }
    }

    // -----------------------------------------------------------------
    // Progressive decoding
    // -----------------------------------------------------------------

    void decodeBlockDcFirst(int ci, int blockX, int blockY)
    {
        ref short p = dcCoeffs_[ci].block(blockX, blockY);

        int s = huffDecode(huff_[comp_[ci].dcTab]);
        if (s > 15) // a magnitude category is at most 15 bits
            throw new JpegException(JpegStatus.decodeError);
        if (s != 0)
        {
            immutable int r = getBitsNoMarkers(s);
            s = huffExtend(r, s);
        }

        lastDcVal_[ci] = (s += lastDcVal_[ci]);
        p = cast(short)(s << successiveLow_);
    }

    void decodeBlockDcRefine(int ci, int blockX, int blockY)
    {
        if (getBitsNoMarkers(1))
        {
            dcCoeffs_[ci].block(blockX, blockY) |= (1 << successiveLow_);
        }
    }

    void decodeBlockAcFirst(int ci, int blockX, int blockY)
    {
        if (eobRun_)
        {
            eobRun_--;
            return;
        }

        ref CoefBlock p = acCoeffs_[ci].block(blockX, blockY);

        for (int k = spectralStart_; k <= spectralEnd_; k++)
        {
            int s = huffDecode(huff_[comp_[ci].acTab]);
            int r = s >> 4;
            s &= 15;

            if (s)
            {
                if ((k += r) > 63)
                    throw new JpegException(JpegStatus.decodeError);

                r = getBitsNoMarkers(s);
                s = huffExtend(r, s);
                p[zigzag[k]] = cast(short)(s << successiveLow_);
            }
            else
            {
                if (r == 15)
                {
                    if ((k += 15) > 63)
                        throw new JpegException(JpegStatus.decodeError);
                }
                else
                {
                    eobRun_ = 1 << r;
                    if (r)
                        eobRun_ += getBitsNoMarkers(r);
                    eobRun_--;
                    break;
                }
            }
        }
    }

    void decodeBlockAcRefine(int ci, int blockX, int blockY)
    {
        immutable int p1 = 1 << successiveLow_;
        immutable int m1 = (-1) << successiveLow_;
        ref CoefBlock p = acCoeffs_[ci].block(blockX, blockY);

        // Adds the next correction bit to a nonzero coefficient.
        void refine(ref short coef)
        {
            if (getBitsNoMarkers(1))
            {
                if ((coef & p1) == 0)
                {
                    if (coef >= 0)
                        coef = cast(short)(coef + p1);
                    else
                        coef = cast(short)(coef + m1);
                }
            }
        }

        int k = spectralStart_;

        if (eobRun_ == 0)
        {
            for (; k <= spectralEnd_; k++)
            {
                int s = huffDecode(huff_[comp_[ci].acTab]);
                int r = s >> 4;
                s &= 15;

                if (s)
                {
                    if (s != 1)
                        throw new JpegException(JpegStatus.decodeError);

                    s = getBitsNoMarkers(1) ? p1 : m1;
                }
                else
                {
                    if (r != 15)
                    {
                        eobRun_ = 1 << r;
                        if (r)
                            eobRun_ += getBitsNoMarkers(r);
                        break;
                    }
                }

                do
                {
                    ref short coef = p[zigzag[k & 63]];

                    if (coef != 0)
                        refine(coef);
                    else
                    {
                        if (--r < 0)
                            break;
                    }

                    k++;
                }
                while (k <= spectralEnd_);

                if (s && k < 64)
                    p[zigzag[k]] = cast(short) s;
            }
        }

        if (eobRun_ > 0)
        {
            for (; k <= spectralEnd_; k++)
            {
                ref short coef = p[zigzag[k & 63]];
                if (coef != 0)
                    refine(coef);
            }

            eobRun_--;
        }
    }

    /// Decodes one scan of a progressive image, block by block.
    void decodeScan(void delegate(int ci, int blockX, int blockY) decodeBlock)
    {
        int[maxComponents] blockXMcu;
        int[maxComponents] blockYMcu;

        foreach (mcuCol; 0 .. mcusPerCol_)
        {
            blockXMcu[] = 0;

            foreach (mcuRow; 0 .. mcusPerRow_)
            {
                int blockXMcuOfs = 0, blockYMcuOfs = 0;

                if (restartInterval_ && restartsLeft_ == 0)
                    processRestart();

                foreach (mcuBlock; 0 .. blocksPerMcu_)
                {
                    immutable int ci = mcuOrg_[mcuBlock];

                    decodeBlock(ci, blockXMcu[ci] + blockXMcuOfs, blockYMcu[ci] + blockYMcuOfs);

                    if (scanComps_ == 1)
                        blockXMcu[ci]++;
                    else if (++blockXMcuOfs == comp_[ci].hSamp)
                    {
                        blockXMcuOfs = 0;

                        if (++blockYMcuOfs == comp_[ci].vSamp)
                        {
                            blockYMcuOfs = 0;
                            blockXMcu[ci] += comp_[ci].hSamp;
                        }
                    }
                }

                restartsLeft_--;
            }

            if (scanComps_ == 1)
                blockYMcu[compList_[0]]++;
            else
                foreach (i; 0 .. scanComps_)
                {
                    immutable int ci = compList_[i];
                    blockYMcu[ci] += comp_[ci].vSamp;
                }
        }
    }

    /// Decodes all the scans of a progressive image into the coefficient buffers.
    void initProgressive()
    {
        if (numComps_ == 4)
            throw new JpegException(JpegStatus.unsupportedColorspace);

        // Allocate the coefficient buffers.
        foreach (ci; 0 .. numComps_)
        {
            immutable int blocksX = maxMcusPerRow_ * comp_[ci].hSamp;
            immutable int blocksY = maxMcusPerCol_ * comp_[ci].vSamp;
            dcCoeffs_[ci] = CoeffBuffer!short(blocksX, blocksY);
            acCoeffs_[ci] = CoeffBuffer!CoefBlock(blocksX, blocksY);
        }

        while (initScan())
        {
            immutable bool dcOnlyScan = spectralStart_ == 0;
            immutable bool refinementScan = successiveHigh_ != 0;

            if (spectralStart_ > spectralEnd_ || spectralEnd_ > 63)
                throw new JpegException(JpegStatus.badSosSpectral);

            if (dcOnlyScan)
            {
                if (spectralEnd_)
                    throw new JpegException(JpegStatus.badSosSpectral);
            }
            else if (scanComps_ != 1) // AC scans can only contain one component
                throw new JpegException(JpegStatus.badSosSpectral);

            if (refinementScan && successiveLow_ != successiveHigh_ - 1)
                throw new JpegException(JpegStatus.badSosSuccessive);

            if (dcOnlyScan)
                decodeScan(refinementScan ? &decodeBlockDcRefine : &decodeBlockDcFirst);
            else
                decodeScan(refinementScan ? &decodeBlockAcRefine : &decodeBlockAcFirst);

            bitsLeft_ = 16;
            getBits(16);
            getBits(16);
        }

        // From here on, rows are read back one MCU row of the whole frame at a time.
        scanComps_ = numComps_;
        foreach (i; 0 .. numComps_)
            compList_[i] = i;

        calcMcuBlockOrder();
    }

    /// Loads and dequantizes the next row of (already decoded) coefficients
    /// of a progressive image.
    void loadNextRow()
    {
        int[maxComponents] blockXMcu;

        foreach (mcuRow; 0 .. mcusPerRow_)
        {
            int blockXMcuOfs = 0, blockYMcuOfs = 0;

            foreach (mcuBlock; 0 .. blocksPerMcu_)
            {
                immutable int ci = mcuOrg_[mcuBlock];
                ref const short[64] q = quant_[comp_[ci].quantSel];

                ref CoefBlock p = mcuCoefs_[mcuBlock];

                immutable int bx = blockXMcu[ci] + blockXMcuOfs;
                immutable int by = blockYMcu_[ci] + blockYMcuOfs;

                p = acCoeffs_[ci].block(bx, by);
                p[0] = dcCoeffs_[ci].block(bx, by);

                // The quantization table is in zig-zag order.
                foreach (i; 0 .. 64)
                    p[zigzag[i]] = cast(short)(p[zigzag[i]] * q[i]);

                if (scanComps_ == 1)
                    blockXMcu[ci]++;
                else if (++blockXMcuOfs == comp_[ci].hSamp)
                {
                    blockXMcuOfs = 0;

                    if (++blockYMcuOfs == comp_[ci].vSamp)
                    {
                        blockYMcuOfs = 0;
                        blockXMcu[ci] += comp_[ci].hSamp;
                    }
                }
            }

            if (freqDomainChromaUpsample_)
                transformMcuExpand(mcuRow);
            else
                transformMcu(mcuRow);
        }

        if (scanComps_ == 1)
            blockYMcu_[compList_[0]]++;
        else
            foreach (i; 0 .. scanComps_)
            {
                immutable int ci = compList_[i];
                blockYMcu_[ci] += comp_[ci].vSamp;
            }
    }

    // -----------------------------------------------------------------
    // Coefficients -> samples
    // -----------------------------------------------------------------

    /// Runs the IDCT over the blocks of one MCU.
    void transformMcu(int mcuRow)
    {
        immutable size_t first = cast(size_t) mcuRow * blocksPerMcu_;
        foreach (b; 0 .. blocksPerMcu_)
            idctBlock(mcuCoefs_[b], sampleBuf_[first + b]);
    }

    /// Like transformMcu, but each chroma block is upsampled to four blocks
    /// in the frequency domain.
    void transformMcuExpand(int mcuRow)
    {
        size_t dst = cast(size_t) mcuRow * expandedBlocksPerMcu_;

        // Y
        foreach (b; 0 .. expandedBlocksPerComponent_)
            idctBlock(mcuCoefs_[b], sampleBuf_[dst++]);

        // Chroma, with upsampling.
        CoefBlock temp;
        foreach (i; 0 .. 2)
        {
            ref const CoefBlock coefs = mcuCoefs_[expandedBlocksPerComponent_ + i];

            Matrix44 p, q, r, s;
            upsampleHalf(coefs, true, p, q);
            upsampleHalf(coefs, false, r, s);

            Matrix44 a, b, c, d;
            foreach (row; 0 .. 4)
                foreach (col; 0 .. 4)
                {
                    a[row][col] = p[row][col] + q[row][col];
                    b[row][col] = p[row][col] - q[row][col];
                    c[row][col] = r[row][col] + s[row][col];
                    d[row][col] = r[row][col] - s[row][col];
                }

            storeSum(temp, a, c, 1);
            idctBlock(temp, sampleBuf_[dst++]);

            storeSum(temp, a, c, -1);
            idctBlock(temp, sampleBuf_[dst++]);

            storeSum(temp, b, d, 1);
            idctBlock(temp, sampleBuf_[dst++]);

            storeSum(temp, b, d, -1);
            idctBlock(temp, sampleBuf_[dst++]);
        }
    }

    // -----------------------------------------------------------------
    // Samples -> scan lines
    // -----------------------------------------------------------------
    //
    // The blocks of an MCU row are laid out MCU after MCU. An MCU holds
    // its Y blocks first, then the Cb block and the Cr block (or, when the
    // chroma was upsampled in the frequency domain, the four Cb blocks and
    // the four Cr blocks).

    /// YCbCr H1V1 (1x1:1:1, 3 blocks per MCU) to RGBA.
    void convertH1V1()
    {
        immutable int at = (maxMcuYSize_ - mcuLinesLeft_) * 8;
        size_t x = 0;

        foreach (mcu; 0 .. maxMcusPerRow_)
        {
            ref const SampleBlock yb = sampleBuf_[3 * mcu];
            ref const SampleBlock cbb = sampleBuf_[3 * mcu + 1];
            ref const SampleBlock crb = sampleBuf_[3 * mcu + 2];
            foreach (j; 0 .. 8)
                putRgba(colorLine0_[x++], yb[at + j], cbb[at + j], crb[at + j]);
        }
    }

    /// YCbCr H2V1 (2x1:1:1, 4 blocks per MCU) to RGBA.
    void convertH2V1()
    {
        immutable int at = (maxMcuYSize_ - mcuLinesLeft_) * 8;
        size_t x = 0;

        foreach (mcu; 0 .. maxMcusPerRow_)
        {
            ref const SampleBlock cbb = sampleBuf_[4 * mcu + 2];
            ref const SampleBlock crb = sampleBuf_[4 * mcu + 3];
            foreach (l; 0 .. 2) // the two Y blocks, each covering 4 chroma samples
            {
                ref const SampleBlock yb = sampleBuf_[4 * mcu + l];
                foreach (j; 0 .. 4)
                {
                    immutable int cb = cbb[at + l * 4 + j];
                    immutable int cr = crb[at + l * 4 + j];
                    putRgba(colorLine0_[x++], yb[at + 2 * j], cb, cr);
                    putRgba(colorLine0_[x++], yb[at + 2 * j + 1], cb, cr);
                }
            }
        }
    }

    /// YCbCr H1V2 (1x2:1:1, 4 blocks per MCU) to RGBA: converts two lines.
    void convertH1V2()
    {
        immutable int row = maxMcuYSize_ - mcuLinesLeft_;
        immutable int yBlock = row < 8 ? 0 : 1;
        immutable int at = (row & 7) * 8; // this line in the Y block
        immutable int cat = (row >> 1) * 8; // the chroma line shared by both
        size_t x = 0;

        foreach (mcu; 0 .. maxMcusPerRow_)
        {
            ref const SampleBlock yb = sampleBuf_[4 * mcu + yBlock];
            ref const SampleBlock cbb = sampleBuf_[4 * mcu + 2];
            ref const SampleBlock crb = sampleBuf_[4 * mcu + 3];
            foreach (j; 0 .. 8)
            {
                immutable int cb = cbb[cat + j];
                immutable int cr = crb[cat + j];
                putRgba(colorLine0_[x], yb[at + j], cb, cr);
                putRgba(colorLine1_[x], yb[at + 8 + j], cb, cr);
                x++;
            }
        }
    }

    /// Y (1 block per MCU) to 8-bit grayscale.
    void convertGray()
    {
        immutable int at = (maxMcuYSize_ - mcuLinesLeft_) * 8;
        foreach (mcu; 0 .. maxMcusPerRow_)
            grayLine_[mcu * 8 .. mcu * 8 + 8] = sampleBuf_[mcu][at .. at + 8];
    }

    /// YCbCr with the chroma already upsampled in the frequency domain to RGBA.
    void expandedConvert()
    {
        immutable int row = maxMcuYSize_ - mcuLinesLeft_;
        immutable int firstBlock = (row / 8) * comp_[0].hSamp; // the Y blocks of this line
        immutable int at = (row & 7) * 8;
        size_t x = 0;

        foreach (mcu; 0 .. maxMcusPerRow_)
        {
            immutable size_t mcuFirst = cast(size_t) mcu * expandedBlocksPerMcu_;
            for (int k = 0; k < maxMcuXSize_ / 8; k++)
            {
                ref const SampleBlock yb = sampleBuf_[mcuFirst + firstBlock + k];
                ref const SampleBlock cbb = sampleBuf_[mcuFirst + expandedBlocksPerComponent_ + firstBlock + k];
                ref const SampleBlock crb = sampleBuf_[mcuFirst + 2 * expandedBlocksPerComponent_ + firstBlock + k];
                foreach (j; 0 .. 8)
                    putRgba(colorLine0_[x++], yb[at + j], cbb[at + j], crb[at + j]);
            }
        }
    }

    /// Finds the end-of-image marker, after the last row is decoded.
    void findEoi()
    {
        if (!progressive_)
        {
            // Prime the bit buffer.
            bitsLeft_ = 16;
            getBits(16);
            getBits(16);

            // The next marker should be EOI, but restarts are allowed as
            // they can harmlessly be skipped at the end of the stream.
            processMarkers(true);
        }
    }
}

// ---------------------------------------------------------------------
// Convenience functions
// ---------------------------------------------------------------------

/// Reads the JPEG header from `read` and reports the image's dimensions
/// and number of components (1 or 3). Returns false if the stream is not
/// a JPEG this decoder understands.
bool detectJpegFromStream(JpegReadFunc read, out int width, out int height, out int actualComps)
{
    if (read is null)
        return false;
    try
    {
        auto decoder = new JpegDecoder(read);
        width = decoder.width;
        height = decoder.height;
        actualComps = decoder.numComponents;
        return true;
    }
    catch (JpegException)
        return false;
}

/// ditto, for a JPEG held in memory.
bool detectJpegFromMemory(const(void)[] data, out int width, out int height, out int actualComps)
{
    return detectJpegFromStream(memoryReader(data), width, height, actualComps);
}

/// ditto, for a JPEG file. Throws if the file cannot be read.
bool detectJpegFromFile(string filename, out int width, out int height, out int actualComps)
{
    auto file = File(filename, "rb");
    return detectJpegFromStream(fileReader(file), width, height, actualComps);
}

/// Decompresses a JPEG image into a tightly packed pixel buffer.
///
/// `reqComps` selects the pixel format: 1 (grayscale), 3 (RGB) or 4 (RGBA,
/// alpha 255); the default, -1, uses the image's own component count (1 or
/// 3). `actualComps` receives the image's own count. Throws `JpegException`
/// if the stream is not a valid, supported JPEG.
ubyte[] decompressJpegFromStream(JpegReadFunc read, out int width, out int height,
    out int actualComps, int reqComps = -1)
{
    if (read is null || (reqComps != -1 && reqComps != 1 && reqComps != 3 && reqComps != 4))
        throw new JpegException(JpegStatus.badArguments);

    auto decoder = new JpegDecoder(read);

    width = decoder.width;
    height = decoder.height;
    actualComps = decoder.numComponents;
    if (reqComps < 0)
        reqComps = actualComps;

    decoder.beginDecoding();

    immutable size_t dstPitch = cast(size_t) width * reqComps;
    auto pixels = new ubyte[](dstPitch * height);

    foreach (y; 0 .. height)
    {
        const(ubyte)[] line = decoder.decodeScanLine();
        convertScanLine(line, pixels[y * dstPitch .. (y + 1) * dstPitch], width, actualComps, reqComps);
    }

    return pixels;
}

/// ditto, for a JPEG held in memory.
ubyte[] decompressJpegFromMemory(const(void)[] data, out int width, out int height,
    out int actualComps, int reqComps = -1)
{
    return decompressJpegFromStream(memoryReader(data), width, height, actualComps, reqComps);
}

/// ditto, for a JPEG file. Throws if the file cannot be read.
ubyte[] decompressJpegFromFile(string filename, out int width, out int height,
    out int actualComps, int reqComps = -1)
{
    auto file = File(filename, "rb");
    return decompressJpegFromStream(fileReader(file), width, height, actualComps, reqComps);
}

/// Converts one decoded scan line (1 byte per pixel for a grayscale image,
/// RGBA otherwise) to `reqComps` bytes per pixel.
private void convertScanLine(const(ubyte)[] src, ubyte[] dst, int width, int srcComps, int reqComps)
    pure nothrow @safe @nogc
{
    if ((reqComps == 1 && srcComps == 1) || (reqComps == 4 && srcComps == 3))
        dst[] = src[0 .. dst.length];
    else if (srcComps == 1)
    {
        // Grayscale to RGB or RGBA.
        foreach (x; 0 .. width)
        {
            immutable ubyte luma = src[x];
            dst[x * reqComps + 0] = luma;
            dst[x * reqComps + 1] = luma;
            dst[x * reqComps + 2] = luma;
            if (reqComps == 4)
                dst[x * reqComps + 3] = 255;
        }
    }
    else if (reqComps == 1)
    {
        // Color to grayscale.
        enum yr = 19595, yg = 38470, yb = 7471;
        foreach (x; 0 .. width)
        {
            immutable int r = src[x * 4 + 0];
            immutable int g = src[x * 4 + 1];
            immutable int b = src[x * 4 + 2];
            dst[x] = cast(ubyte)((r * yr + g * yg + b * yb + 32768) >> 16);
        }
    }
    else
    {
        // RGBA to RGB.
        foreach (x; 0 .. width)
        {
            dst[x * 3 + 0] = src[x * 4 + 0];
            dst[x * 3 + 1] = src[x * 4 + 1];
            dst[x * 3 + 2] = src[x * 4 + 2];
        }
    }
}

/// A `JpegReadFunc` over a block of memory.
private JpegReadFunc memoryReader(const(void)[] data)
{
    auto bytes = cast(const(ubyte)[]) data;
    size_t pos;
    return (ubyte[] buffer, out bool endOfStream)
    {
        immutable size_t n = bytes.length - pos < buffer.length ? bytes.length - pos : buffer.length;
        buffer[0 .. n] = bytes[pos .. pos + n];
        pos += n;
        endOfStream = pos >= bytes.length;
        return n;
    };
}

/// A `JpegReadFunc` over an open file.
private JpegReadFunc fileReader(ref File file)
{
    return (ubyte[] buffer, out bool endOfStream)
    {
        auto got = file.rawRead(buffer);
        if (got.length < buffer.length)
            endOfStream = true;
        return got.length;
    };
}

// ---------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------

unittest
{
    // Not a JPEG at all.
    int w, h, c;
    ubyte[] junk = [1, 2, 3, 4, 5, 6, 7, 8];
    assert(!detectJpegFromMemory(junk, w, h, c));

    bool threw;
    try
        decompressJpegFromMemory(junk, w, h, c);
    catch (JpegException e)
        threw = true;
    assert(threw);
}

unittest
{
    // Argument validation.
    int w, h, c;
    bool threw;
    try
        decompressJpegFromMemory(new ubyte[](10), w, h, c, 2);
    catch (JpegException e)
        threw = e.status == JpegStatus.badArguments;
    assert(threw);
}

unittest
{
    // Decoder output must stay identical to jpgd: SHA-1 of the RGB pixels of
    // small 45x29 JPEGs (made with the IJG `cjpeg`), as decoded by jpgd.
    import std.digest.sha : sha1Of, toHexString;

    static struct Golden { string what; immutable(ubyte)[] jpeg; string decoded; }
    static immutable Golden[] golden = [
        Golden("baseline H2V2 with restart markers", [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xDB, 0x00, 0x43, 0x00, 0x0A, 0x07, 0x07, 0x08, 0x07, 0x06, 0x0A, 0x08, 0x08, 0x08, 0x0B, 0x0A, 0x0A, 0x0B, 0x0E,
            0x18, 0x10, 0x0E, 0x0D, 0x0D, 0x0E, 0x1D, 0x15, 0x16, 0x11, 0x18, 0x23, 0x1F, 0x25, 0x24, 0x22, 0x1F, 0x22, 0x21, 0x26,
            0x2B, 0x37, 0x2F, 0x26, 0x29, 0x34, 0x29, 0x21, 0x22, 0x30, 0x41, 0x31, 0x34, 0x39, 0x3B, 0x3E, 0x3E, 0x3E, 0x25, 0x2E,
            0x44, 0x49, 0x43, 0x3C, 0x48, 0x37, 0x3D, 0x3E, 0x3B, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x0A, 0x0B, 0x0B, 0x0E, 0x0D, 0x0E,
            0x1C, 0x10, 0x10, 0x1C, 0x3B, 0x28, 0x22, 0x28, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0xFF, 0xC0,
            0x00, 0x11, 0x08, 0x00, 0x1D, 0x00, 0x2D, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
            0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03, 0x03,
            0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
            0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15,
            0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29,
            0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56,
            0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A,
            0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4,
            0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6,
            0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7,
            0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xC4, 0x00, 0x1F, 0x01, 0x00, 0x03,
            0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
            0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x11, 0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07,
            0x05, 0x04, 0x04, 0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51,
            0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15,
            0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35,
            0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
            0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84,
            0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6,
            0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8,
            0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
            0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDD, 0x00, 0x04, 0x00, 0x06, 0xFF, 0xDA, 0x00, 0x0C, 0x03,
            0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3F, 0x00, 0xF2, 0xF8, 0xAC, 0x3D, 0xAA, 0xEC, 0x36, 0x3D, 0x38, 0xAD, 0x78,
            0xAC, 0x7D, 0xAA, 0xEC, 0x36, 0x1D, 0x38, 0xF4, 0xAB, 0xA7, 0x33, 0x9B, 0x0F, 0x8D, 0xF3, 0x32, 0x62, 0xB0, 0xE9, 0xC5,
            0x5D, 0x8A, 0xC7, 0xDA, 0xB5, 0xE1, 0xB1, 0xE9, 0xC7, 0xA5, 0x5D, 0x8A, 0xC3, 0xDA, 0xBB, 0xA9, 0xCC, 0xFA, 0x0C, 0x3E,
            0x37, 0xCC, 0xCA, 0x8A, 0xC3, 0xDA, 0xAE, 0x25, 0x8F, 0x1D, 0x2B, 0x62, 0x2B, 0x0F, 0x6A, 0xB8, 0x96, 0x3C, 0x74, 0xAE,
            0xD8, 0x4C, 0xF7, 0xE8, 0x63, 0x74, 0xDC, 0xC0, 0x8A, 0xC3, 0xFD, 0x9A, 0xBB, 0x15, 0x87, 0x4E, 0x2B, 0x4E, 0x2B, 0x74,
            0xE2, 0xAF, 0x45, 0x6C, 0x9C, 0x57, 0xCC, 0xD3, 0x99, 0xF8, 0x76, 0x1F, 0x18, 0xCC, 0xC8, 0xAC, 0x3A, 0x7C, 0xB5, 0x76,
            0x2B, 0x0F, 0x6A, 0xD4, 0x8A, 0xD9, 0x38, 0xAB, 0xB1, 0x5B, 0x25, 0x76, 0xC2, 0x67, 0xD0, 0x61, 0xF1, 0x8C, 0xCC, 0x8A,
            0xC7, 0x03, 0x24, 0x60, 0x01, 0x43, 0xA3, 0xEE, 0x22, 0x3C, 0x00, 0x0F, 0x51, 0xCE, 0x6B, 0x5A, 0x74, 0x0B, 0x88, 0xC6,
            0x46, 0x57, 0x24, 0xFA, 0xD2, 0xA5, 0xB2, 0x62, 0xBE, 0x5F, 0x3A, 0xCE, 0xAA, 0x46, 0x7F, 0x57, 0xA0, 0xDA, 0xB6, 0xED,
            0x68, 0xFD, 0x11, 0xF5, 0x18, 0x3C, 0x43, 0xB5, 0xD9, 0xFF, 0xD9,
        ], "8FC4B6B02C856985238CD80FA31256CA4E7040F4"),
        Golden("progressive H2V2", [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xDB, 0x00, 0x43, 0x00, 0x0A, 0x07, 0x07, 0x08, 0x07, 0x06, 0x0A, 0x08, 0x08, 0x08, 0x0B, 0x0A, 0x0A, 0x0B, 0x0E,
            0x18, 0x10, 0x0E, 0x0D, 0x0D, 0x0E, 0x1D, 0x15, 0x16, 0x11, 0x18, 0x23, 0x1F, 0x25, 0x24, 0x22, 0x1F, 0x22, 0x21, 0x26,
            0x2B, 0x37, 0x2F, 0x26, 0x29, 0x34, 0x29, 0x21, 0x22, 0x30, 0x41, 0x31, 0x34, 0x39, 0x3B, 0x3E, 0x3E, 0x3E, 0x25, 0x2E,
            0x44, 0x49, 0x43, 0x3C, 0x48, 0x37, 0x3D, 0x3E, 0x3B, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x0A, 0x0B, 0x0B, 0x0E, 0x0D, 0x0E,
            0x1C, 0x10, 0x10, 0x1C, 0x3B, 0x28, 0x22, 0x28, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0xFF, 0xC2,
            0x00, 0x11, 0x08, 0x00, 0x1D, 0x00, 0x2D, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
            0x17, 0x00, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x03,
            0x00, 0x06, 0xFF, 0xC4, 0x00, 0x17, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x05, 0x03, 0x01, 0x06, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x10, 0x03, 0x10, 0x00, 0x00,
            0x01, 0xE5, 0xEC, 0xCB, 0x6C, 0x89, 0x75, 0xDE, 0xE8, 0x12, 0xCC, 0xB5, 0xD0, 0x05, 0x95, 0x73, 0x38, 0x62, 0xDD, 0x56,
            0xB2, 0x06, 0xCB, 0xC5, 0xA9, 0xFF, 0xC4, 0x00, 0x18, 0x10, 0x00, 0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x12, 0x10, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x05,
            0x02, 0x50, 0x28, 0x14, 0x0A, 0x05, 0x06, 0x05, 0x02, 0x81, 0x40, 0xA0, 0x50, 0x60, 0x50, 0x28, 0x14, 0x0A, 0x05, 0x1C,
            0x52, 0x29, 0x14, 0x8A, 0x46, 0x64, 0xFF, 0xC4, 0x00, 0x16, 0x11, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x02, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x03, 0x01, 0x01, 0x3F, 0x01,
            0x36, 0x8D, 0xAC, 0x34, 0x6D, 0x1B, 0x42, 0x97, 0xFF, 0xC4, 0x00, 0x18, 0x11, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x04, 0x13, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x02,
            0x01, 0x01, 0x3F, 0x01, 0xCB, 0x65, 0x86, 0xCB, 0x0D, 0xDB, 0xDB, 0xA1, 0xF3, 0xC5, 0xFF, 0xC4, 0x00, 0x18, 0x10, 0x00,
            0x02, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x11, 0x20, 0x21, 0x40,
            0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x06, 0x3F, 0x02, 0xC3, 0x51, 0x43, 0xFF, 0xC4, 0x00, 0x1A, 0x10, 0x01, 0x01,
            0x00, 0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x10, 0x11, 0x20, 0x61,
            0x81, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x3F, 0x21, 0xE5, 0xD5, 0x3A, 0xBE, 0xA5, 0xF1, 0xC3, 0xE3, 0x95,
            0x47, 0x70, 0x20, 0x82, 0x08, 0xEB, 0xE2, 0x05, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x00,
            0x00, 0x10, 0x5E, 0xBF, 0x11, 0x9C, 0x7F, 0xFF, 0xC4, 0x00, 0x19, 0x11, 0x00, 0x02, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x11, 0x21, 0x61, 0x31, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x03,
            0x01, 0x01, 0x3F, 0x10, 0xD4, 0xD4, 0xAF, 0xA3, 0x06, 0x0C, 0x89, 0x67, 0xFF, 0xC4, 0x00, 0x1A, 0x11, 0x01, 0x00, 0x01,
            0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x11, 0x00, 0x20, 0x21, 0x31, 0x71,
            0xFF, 0xDA, 0x00, 0x08, 0x01, 0x02, 0x01, 0x01, 0x3F, 0x10, 0xB5, 0x77, 0x90, 0xA9, 0x1B, 0x4C, 0x3C, 0x2B, 0xFF, 0xC4,
            0x00, 0x1B, 0x10, 0x00, 0x02, 0x03, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x11, 0x21, 0x31, 0x61, 0x51, 0x10, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x3F, 0x10, 0xE6, 0x61, 0x46,
            0x74, 0x72, 0x39, 0x95, 0x61, 0xC8, 0xC6, 0xBC, 0x30, 0xAF, 0x0E, 0x67, 0x32, 0xAC, 0xF9, 0xB3, 0xA3, 0x31, 0xCC, 0x89,
            0x4B, 0x50, 0x92, 0x27, 0x94, 0x12, 0x4F, 0x55, 0xC9, 0x54, 0xAE, 0x57, 0xF9, 0xD7, 0x04, 0x95, 0x32, 0x6F, 0xD2, 0x39,
            0xFF, 0xD9,
        ], "8FC4B6B02C856985238CD80FA31256CA4E7040F4"),
        Golden("progressive grayscale", [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xDB, 0x00, 0x43, 0x00, 0x0A, 0x07, 0x07, 0x08, 0x07, 0x06, 0x0A, 0x08, 0x08, 0x08, 0x0B, 0x0A, 0x0A, 0x0B, 0x0E,
            0x18, 0x10, 0x0E, 0x0D, 0x0D, 0x0E, 0x1D, 0x15, 0x16, 0x11, 0x18, 0x23, 0x1F, 0x25, 0x24, 0x22, 0x1F, 0x22, 0x21, 0x26,
            0x2B, 0x37, 0x2F, 0x26, 0x29, 0x34, 0x29, 0x21, 0x22, 0x30, 0x41, 0x31, 0x34, 0x39, 0x3B, 0x3E, 0x3E, 0x3E, 0x25, 0x2E,
            0x44, 0x49, 0x43, 0x3C, 0x48, 0x37, 0x3D, 0x3E, 0x3B, 0xFF, 0xC2, 0x00, 0x0B, 0x08, 0x00, 0x1D, 0x00, 0x2D, 0x01, 0x01,
            0x11, 0x00, 0xFF, 0xC4, 0x00, 0x18, 0x00, 0x01, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x03, 0x00, 0x02, 0x04, 0x06, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 0xE5, 0xD9,
            0xDD, 0xDB, 0x03, 0x3B, 0xBB, 0x60, 0x67, 0x77, 0x99, 0x1D, 0xDA, 0xD3, 0xFF, 0xC4, 0x00, 0x18, 0x10, 0x00, 0x03, 0x01,
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x12, 0x10, 0xFF, 0xDA,
            0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x05, 0x02, 0x50, 0x28, 0x14, 0x0A, 0x05, 0x06, 0x05, 0x02, 0x81, 0x40, 0xA0, 0x50,
            0x60, 0x50, 0x28, 0x14, 0x0A, 0x05, 0x1C, 0x52, 0x29, 0x14, 0x8A, 0x46, 0x64, 0xFF, 0xC4, 0x00, 0x18, 0x10, 0x00, 0x02,
            0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x11, 0x20, 0x21, 0x40, 0xFF,
            0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x06, 0x3F, 0x02, 0xC3, 0x51, 0x43, 0xFF, 0xC4, 0x00, 0x1A, 0x10, 0x01, 0x01, 0x00,
            0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x10, 0x11, 0x20, 0x61, 0x81,
            0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x3F, 0x21, 0xE5, 0xD5, 0x3A, 0xBE, 0xA5, 0xF1, 0xC3, 0xE3, 0x95, 0x47,
            0x70, 0x20, 0x82, 0x08, 0xEB, 0xE2, 0x05, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x00, 0x10, 0x6D, 0xB6, 0x05,
            0xFF, 0xC4, 0x00, 0x1B, 0x10, 0x00, 0x02, 0x03, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x01, 0x11, 0x21, 0x31, 0x61, 0x51, 0x10, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x3F, 0x10, 0xE6,
            0x61, 0x46, 0x74, 0x72, 0x39, 0x95, 0x61, 0xC8, 0xC6, 0xBC, 0x30, 0xAF, 0x0E, 0x67, 0x32, 0xAC, 0xF9, 0xB3, 0xA3, 0x31,
            0xCC, 0x89, 0x4B, 0x50, 0x92, 0x27, 0x94, 0x12, 0x4F, 0x55, 0xC9, 0x54, 0xAE, 0x57, 0xF9, 0xD7, 0x04, 0x95, 0x32, 0x6F,
            0xD2, 0x39, 0xFF, 0xD9,
        ], "538D59F4D4FA45C47E7B70B392C32FE9377335A0"),
        Golden("progressive H1V2 with restart markers", [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xDB, 0x00, 0x43, 0x00, 0x0A, 0x07, 0x07, 0x08, 0x07, 0x06, 0x0A, 0x08, 0x08, 0x08, 0x0B, 0x0A, 0x0A, 0x0B, 0x0E,
            0x18, 0x10, 0x0E, 0x0D, 0x0D, 0x0E, 0x1D, 0x15, 0x16, 0x11, 0x18, 0x23, 0x1F, 0x25, 0x24, 0x22, 0x1F, 0x22, 0x21, 0x26,
            0x2B, 0x37, 0x2F, 0x26, 0x29, 0x34, 0x29, 0x21, 0x22, 0x30, 0x41, 0x31, 0x34, 0x39, 0x3B, 0x3E, 0x3E, 0x3E, 0x25, 0x2E,
            0x44, 0x49, 0x43, 0x3C, 0x48, 0x37, 0x3D, 0x3E, 0x3B, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x0A, 0x0B, 0x0B, 0x0E, 0x0D, 0x0E,
            0x1C, 0x10, 0x10, 0x1C, 0x3B, 0x28, 0x22, 0x28, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0xFF, 0xC2,
            0x00, 0x11, 0x08, 0x00, 0x1D, 0x00, 0x2D, 0x03, 0x01, 0x12, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
            0x16, 0x00, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x05,
            0x06, 0xFF, 0xC4, 0x00, 0x19, 0x01, 0x01, 0x01, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x04, 0x02, 0x00, 0x03, 0x05, 0x07, 0xFF, 0xDD, 0x00, 0x04, 0x00, 0x12, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01,
            0x00, 0x02, 0x10, 0x03, 0x10, 0x00, 0x00, 0x01, 0xCB, 0xD2, 0xC3, 0x8E, 0x95, 0xEF, 0x25, 0x2B, 0x41, 0x29, 0x6C, 0x41,
            0x29, 0x5A, 0x07, 0x4A, 0xD0, 0x0A, 0x1C, 0x9F, 0x3E, 0x2D, 0x1D, 0x88, 0x2D, 0x1B, 0x41, 0x68, 0x5A, 0x0C, 0xB3, 0x28,
            0x8B, 0xE3, 0x33, 0xFF, 0xC4, 0x00, 0x18, 0x10, 0x00, 0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x12, 0x10, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x05, 0x02, 0x50,
            0x28, 0x14, 0x0A, 0x05, 0x06, 0x05, 0x02, 0x81, 0x40, 0xA0, 0x50, 0x60, 0x50, 0x28, 0x14, 0x0A, 0x05, 0x1C, 0xFF, 0xD0,
            0x52, 0x29, 0x14, 0x8A, 0x46, 0x64, 0xFF, 0xC4, 0x00, 0x17, 0x11, 0x00, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x03, 0x01, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x03, 0x01, 0x01, 0x3F,
            0x01, 0x5B, 0x0B, 0x61, 0x6C, 0x2D, 0x85, 0xB1, 0x97, 0x16, 0xC2, 0xD8, 0x5B, 0x0B, 0x61, 0x29, 0xBA, 0x2D, 0x0F, 0xFF,
            0xC4, 0x00, 0x1B, 0x11, 0x01, 0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x03, 0x04, 0x11, 0x02, 0x21, 0x41, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x02, 0x01, 0x01, 0x3F, 0x01, 0x18, 0x61,
            0x86, 0x1B, 0xB0, 0xC3, 0x0C, 0x36, 0xC6, 0xEF, 0x9C, 0x1F, 0x3F, 0x6C, 0x9B, 0xB9, 0xBD, 0xBD, 0xEF, 0x2F, 0xFF, 0xC4,
            0x00, 0x19, 0x10, 0x00, 0x01, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x10, 0x11, 0x20, 0x21, 0x40, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x06, 0x3F, 0x02, 0xC3, 0x47, 0xFF, 0xD0, 0x83,
            0x27, 0xFF, 0xC4, 0x00, 0x1A, 0x10, 0x01, 0x01, 0x00, 0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x01, 0x00, 0x10, 0x11, 0x20, 0x61, 0x81, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x3F, 0x21, 0xE5,
            0xD5, 0x3A, 0xBE, 0xA5, 0xF1, 0xC3, 0xE3, 0x95, 0x47, 0x73, 0xFF, 0xD0, 0x08, 0x20, 0x82, 0x3A, 0xF8, 0x81, 0x7F, 0xFF,
            0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x00, 0x00, 0x10, 0x0E, 0xF0, 0xFE, 0x18, 0x96, 0x37, 0xFF,
            0xC4, 0x00, 0x19, 0x11, 0x01, 0x01, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x01, 0x61, 0x10, 0x21, 0x31, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x03, 0x01, 0x01, 0x3F, 0x10, 0xD5, 0xAB, 0x56, 0xAD,
            0x5D, 0x1E, 0xA8, 0xA2, 0x8A, 0x71, 0x10, 0x91, 0xFF, 0xC4, 0x00, 0x1B, 0x11, 0x01, 0x00, 0x02, 0x02, 0x03, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x11, 0x20, 0x21, 0x51, 0xB1, 0xD1, 0xFF, 0xDA, 0x00,
            0x08, 0x01, 0x02, 0x01, 0x01, 0x3F, 0x10, 0xC5, 0x55, 0x31, 0xA8, 0xEE, 0x85, 0xB2, 0xC3, 0xD6, 0x29, 0xB4, 0x70, 0x35,
            0xD4, 0xFF, 0xC4, 0x00, 0x1B, 0x10, 0x00, 0x02, 0x03, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x01, 0x11, 0x21, 0x31, 0x61, 0x51, 0x10, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x01, 0x3F, 0x10,
            0xE6, 0x61, 0x46, 0x74, 0x72, 0x39, 0x95, 0x61, 0xC8, 0xC6, 0xBC, 0x30, 0xAF, 0x0E, 0x67, 0x32, 0xAC, 0xF9, 0xB3, 0xA3,
            0x31, 0xCC, 0x89, 0x4B, 0x50, 0x92, 0x27, 0x94, 0x12, 0x4F, 0x55, 0xC9, 0xFF, 0xD0, 0xAA, 0x57, 0x2B, 0xFC, 0xEB, 0x82,
            0x4A, 0x99, 0x37, 0xE9, 0x1C, 0xFF, 0xD9,
        ], "9C7C2F4A90C3B3600FE38640FED5312245562DF0"),
        Golden("baseline H2V1", [
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            0xFF, 0xDB, 0x00, 0x43, 0x00, 0x0A, 0x07, 0x07, 0x08, 0x07, 0x06, 0x0A, 0x08, 0x08, 0x08, 0x0B, 0x0A, 0x0A, 0x0B, 0x0E,
            0x18, 0x10, 0x0E, 0x0D, 0x0D, 0x0E, 0x1D, 0x15, 0x16, 0x11, 0x18, 0x23, 0x1F, 0x25, 0x24, 0x22, 0x1F, 0x22, 0x21, 0x26,
            0x2B, 0x37, 0x2F, 0x26, 0x29, 0x34, 0x29, 0x21, 0x22, 0x30, 0x41, 0x31, 0x34, 0x39, 0x3B, 0x3E, 0x3E, 0x3E, 0x25, 0x2E,
            0x44, 0x49, 0x43, 0x3C, 0x48, 0x37, 0x3D, 0x3E, 0x3B, 0xFF, 0xDB, 0x00, 0x43, 0x01, 0x0A, 0x0B, 0x0B, 0x0E, 0x0D, 0x0E,
            0x1C, 0x10, 0x10, 0x1C, 0x3B, 0x28, 0x22, 0x28, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B,
            0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0x3B, 0xFF, 0xC0,
            0x00, 0x11, 0x08, 0x00, 0x1D, 0x00, 0x2D, 0x03, 0x01, 0x21, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01, 0xFF, 0xC4, 0x00,
            0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
            0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03, 0x03,
            0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
            0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15,
            0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29,
            0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56,
            0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A,
            0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4,
            0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6,
            0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7,
            0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xC4, 0x00, 0x1F, 0x01, 0x00, 0x03,
            0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
            0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x11, 0x00, 0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07,
            0x05, 0x04, 0x04, 0x00, 0x01, 0x02, 0x77, 0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51,
            0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15,
            0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x35,
            0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
            0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84,
            0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6,
            0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8,
            0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
            0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x0C, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11,
            0x00, 0x3F, 0x00, 0xF2, 0xF8, 0xAC, 0x3D, 0xAA, 0xEC, 0x36, 0x3D, 0x38, 0xAD, 0xA0, 0xCD, 0x30, 0xF5, 0xCB, 0xD1, 0x58,
            0x74, 0xE2, 0xAE, 0xC5, 0x63, 0xED, 0x5D, 0xD4, 0xD9, 0xEF, 0xE1, 0xEB, 0x97, 0xE2, 0xB0, 0xF6, 0xAB, 0x89, 0x63, 0xC7,
            0x4A, 0xED, 0x83, 0x3E, 0x82, 0x85, 0x7D, 0x0C, 0x08, 0xAC, 0x7D, 0xAA, 0xEC, 0x36, 0x1D, 0x38, 0xF4, 0xAF, 0x9E, 0xA7,
            0x23, 0xF2, 0x6C, 0x3D, 0x72, 0xF4, 0x36, 0x3D, 0x38, 0xF4, 0xAB, 0xB1, 0x58, 0x7B, 0x57, 0x75, 0x39, 0x1F, 0x41, 0x87,
            0xAE, 0x5F, 0x8A, 0xC3, 0xDA, 0xAE, 0x25, 0x8F, 0x1D, 0x2B, 0xB6, 0x12, 0x3D, 0xFA, 0x15, 0xF4, 0x30, 0x22, 0xB0, 0xFF,
            0x00, 0x66, 0xAE, 0xC5, 0x61, 0xD3, 0x8A, 0xF9, 0xEA, 0x6C, 0xFC, 0x9B, 0x0F, 0x5C, 0xBD, 0x15, 0x87, 0x4F, 0x96, 0xAE,
            0xC5, 0x61, 0xED, 0x5D, 0xD4, 0xE4, 0x7D, 0x06, 0x1E, 0xB9, 0x7A, 0x2B, 0x1C, 0x0C, 0x91, 0x80, 0x05, 0x0E, 0x8F, 0xB8,
            0x88, 0xF0, 0x00, 0x3D, 0x47, 0x39, 0xAF, 0x3B, 0x39, 0xCC, 0xA7, 0x83, 0xA2, 0x95, 0x27, 0x69, 0x37, 0xF3, 0x4B, 0xBD,
            0xBF, 0x03, 0xE9, 0x70, 0x75, 0x14, 0xB7, 0x32, 0x62, 0xB7, 0x4E, 0x2A, 0xF4, 0x56, 0xC9, 0xC5, 0x4D, 0x36, 0x7E, 0x47,
            0x87, 0xA8, 0xCB, 0xD1, 0x5B, 0x27, 0x15, 0x76, 0x2B, 0x64, 0xAE, 0xE8, 0x33, 0xE8, 0x30, 0xF5, 0x18, 0xF9, 0xD0, 0x2E,
            0x23, 0x19, 0x19, 0x5C, 0x93, 0xEB, 0x4A, 0x96, 0xC9, 0x8A, 0xF8, 0x0C, 0xEF, 0x13, 0x2A, 0xB8, 0xD9, 0x27, 0xB4, 0x74,
            0x47, 0xD6, 0x60, 0xE6, 0xF9, 0x0F, 0xFF, 0xD9,
        ], "47EFA4D0BE4AD0F9CC8B25BE9D254A9AA9450EC1"),
    ];

    foreach (g; golden)
    {
        int w, h, c;
        auto pixels = decompressJpegFromMemory(g.jpeg, w, h, c, 3);
        assert(w == 45 && h == 29, g.what);
        assert(toHexString(sha1Of(pixels)) == g.decoded, g.what);
    }
}
