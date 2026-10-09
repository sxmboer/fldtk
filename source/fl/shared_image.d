/*
 * Ported from FL/Fl_Shared_Image.H + src/Fl_Shared_Image.cxx (FLTK
 * 1.5.0): Fl_Shared_Image, a filename-keyed,
 * reference-counted image cache. Loading the same file (e.g. a
 * toolbar icon used by a dozen buttons) through `get()` returns the
 * *same* in-memory image after the first load, only actually
 * releasing it once every caller has released() its own reference.
 *
 * Format detection: FLTK hardcodes XBM (`"#define"` header) and
 * XPM (`"/* XPM *"~"/"` header) detection directly in `reload()`,
 * with everything else (JPEG/PNG/GIF/BMP/ICO/SVG in real FLTK,
 * registered by the separate `fltk_images` library's own
 * `fl_register_images()`) going through a pluggable handler chain
 * (`add_handler()`/`remove_handler()`). This port follows the same
 * split: XBM/XPM detection stays hardcoded (matching FLTK exactly,
 * both being genuinely built into this port's own core `fl.image`
 * now, not optional/pluggable), **PNM detection is hardcoded here too
 * for the same reason** (`fl.pnm_image` is just as much a core,
 * always-available part of this port as XBM/XPM are, unlike FLTK
 * where PNM support is *also* only ever added via the same external
 * `fltk_images`-registered handler as JPEG/PNG). GIF/BMP/ICO/SVG stay
 * behind `registerImages()`'s `addHandler()` chain, matching FLTK's
 * own choice not to hardcode those either -- GIF/BMP/ICO/SVG/PNG/JPEG
 * are all real, native decoders, see `registerImages()`'s
 * own doc comment below for the handler that actually registers them.
 * They still go
 * through the same real, public `addHandler()`/`removeHandler()`
 * extension point FLTK exposes, so user code can already register
 * its own format support today exactly as FLTK's own documentation
 * describes.
 *
 * Deliberate simplifications from FLTK, all documented at their
 * point of use below:
 *  - **The image pool is a plain linear-scan D array**, not FLTK's
 *    hand-`qsort()`-sorted-and-`bsearch()`-searched C array. A typical
 *    app has at most dozens of shared images (icons, toolbar
 *    pixmaps, ...), where a linear scan costs nothing measurable --
 *    the sorted/binary-search machinery exists FLTK purely as a
 *    C-era performance optimization this port doesn't need, same
 *    "simpler, exactly as capable for every case this port exercises"
 *    reasoning CONVENTIONS.md documents elsewhere (e.g. `fl.tabs`'s storage
 *    simplification).
 *  - **No generic `data()`/`count()` aliasing** in `update()` --
 *    FLTK's `update()` also calls `data(image_->data(),
 *    image_->count())` so a caller holding only a base `Fl_Image*` can
 *    still reach the wrapped image's raw pixel data without knowing
 *    its concrete type. This port never ported that generic accessor
 *    at all (see `fl.image`'s own top comment) -- callers reach the
 *    wrapped image directly via `image()` instead, which FLTK
 *    itself documents as the recommended access path anyway.
 *  - **The non-`const` refcount-bump-and-return-self `copy()`
 *    overload is renamed `retain()`.** FLTK genuinely has three
 *    different `copy()` overloads on this class -- a `const`
 *    `copy(int,int)` (makes a real resized copy via `get()`), a
 *    `const` `copy()` (equivalent to the inherited `Fl_Image::copy()`
 *    forwarder), and a **non-`const`** `copy()` that does something
 *    completely different (just increments the refcount and returns
 *    `this`) -- selected purely by whether the *caller's own
 *    reference* happens to be `const` at the call site. D supports
 *    overloading by receiver constness too, but silently picking
 *    between "make a real copy" and "return the same object with a
 *    bumped refcount" based on constness reads as confusing API
 *    design even in C++; giving the refcount-only path its own name
 *    removes an easy-to-misuse footgun rather than faithfully
 *    preserving it.
 */
module fl.shared_image;

import fl.image : Image, RGBImage;
import fl.enumerations : Color;
import fl.xbm_image : XBMImage;
import fl.xpm_image : XPMImage;
import fl.pnm_image : PNMImage;

/// A format-detection handler: given a filename and up to the first
/// 64 bytes of its content, either returns a loaded Image or null (if
/// this handler doesn't recognize the format). Ported from
/// `Fl_Shared_Handler` -- a D delegate instead of a C function
/// pointer, matching CONVENTIONS.md's usual callback-porting convention
/// (nothing here needs a separate `void*` user-data slot the way
/// FLTK's plain function pointer would, since a delegate already
/// closes over whatever state it needs).
alias SharedHandler = Image delegate(string name, const(ubyte)[] header);

class SharedImage : Image
{
    private static SharedImage[] images_;
    private static SharedHandler[] handlers_;

    private string name_;
    private bool original_;
    private int refcount_;
    private Image image_;
    private bool allocImage_;

    private this()
    {
        super(0, 0, 0);
        refcount_ = 1;
    }

    private this(string n, Image img = null)
    {
        super(0, 0, 0);
        name_ = n;
        refcount_ = 1;
        image_ = img;
        allocImage_ = img is null;
        original_ = true;
        if (img is null) reload();
        else update();
    }

    private void add()
    {
        images_ ~= this;
    }

    /// Adds `img` to the pool under `name`, so a later `get(name)`/
    /// `find(name)` returns it -- what FLTK's in-memory image
    /// constructors (`Fl_PNG_Image`, `Fl_JPEG_Image`, `Fl_SVG_Image`) do
    /// with a non-null name: `new Fl_Shared_Image(name, this); si->add();`.
    package(fl) static void addNamed(string name, Image img)
    {
        (new SharedImage(name, img)).add();
    }

    private void update()
    {
        if (image_ !is null)
        {
            int W = w(), H = h();
            w(image_.dataW());
            h(image_.dataH());
            d(image_.d());
            if (W != 0 && H != 0) scale(W, H, false, true);
        }
    }

    /// The filename (or pool name, for get(RGBImage)) this shared
    /// image was loaded/created from.
    string name() const { return name_; }

    /// How many callers currently hold a reference (via get()/find()/
    /// retain()) -- the image is actually destroyed once this reaches 0.
    int refcount() const { return refcount_; }

    /// True for an image loaded directly from a file/RGBImage, false
    /// for a resized copy of one (see get()'s own doc comment on the
    /// "original, plus one resized copy per requested size" caching
    /// model).
    bool original() const { return original_; }

    alias copy = Image.copy; // re-expose the 0-arg overload the override below hides
    alias draw = Image.draw; // ditto

    override void release()
    {
        if (refcount_ <= 0) return;
        refcount_--;
        if (refcount_ > 0) return;

        SharedImage theOriginal;
        if (!original_)
        {
            auto o = find(name_);
            if (o !is null)
            {
                if (o.original_ && o !is this && o.refcount_ > 1)
                    theOriginal = o;
                o.release();
            }
        }

        foreach (i, im; images_)
        {
            if (im is this)
            {
                images_ = images_[0 .. i] ~ images_[i + 1 .. $];
                break;
            }
        }

        if (theOriginal !is null) theOriginal.release();
    }

    /// Reloads the shared image from disk, re-sniffing its format --
    /// called automatically by the loading constructor; only useful to
    /// call directly if the file on disk changed since it was loaded.
    void reload()
    {
        import std.file : read;

        if (name_ is null) return;

        ubyte[] header;
        try
            header = cast(ubyte[]) read(name_, 64);
        catch (Exception)
            return;
        if (header.length == 0) return;

        Image img;
        if (header.length >= 7 && cast(string) header[0 .. 7] == "#define")
            img = new XBMImage(name_);
        else if (header.length >= 9 && cast(string) header[0 .. 9] == "/* XPM */")
            img = new XPMImage(name_);
        else if (header.length >= 2 && header[0] == 'P' && header[1] >= '1' && header[1] <= '7')
            img = new PNMImage(name_);
        else
        {
            foreach (h; handlers_)
            {
                img = h(name_, header);
                if (img !is null) break;
            }
        }

        if (img !is null)
        {
            allocImage_ = true;
            image_ = img;
            int W = w(), H = h();
            update();
            if (W != 0) scale(W, H, false, true);
        }
    }

    private SharedImage copyImpl(int W, int H) const
    {
        Image tempImage = image_ !is null ? image_.copy(W, H) : null;
        auto tempShared = new SharedImage();
        tempShared.name_ = name_;
        tempShared.refcount_ = 1;
        tempShared.image_ = tempImage;
        tempShared.allocImage_ = true;
        tempShared.update();
        return tempShared;
    }

    /// Returns a shared image of this image at the requested size --
    /// equivalent to `get(name(), W, H)`. If a shared image of that
    /// size already exists in the pool, the existing image is
    /// returned (with its refcount bumped), no new copy made.
    override Image copy(int W, int H) const
    {
        return name_ !is null ? get(name_, W, H) : null;
    }

    /// Bumps the reference count and returns this -- see the module's
    /// own top comment for why this has its own name rather than
    /// reusing `copy()` the way FLTK's non-`const` overload does.
    SharedImage retain()
    {
        refcount_++;
        return this;
    }

    override void colorAverage(Color c, float i)
    {
        if (image_ is null) return;
        image_.colorAverage(c, i);
        update();
    }

    override void desaturate()
    {
        if (image_ is null) return;
        image_.desaturate();
        update();
    }

    override void draw(int X, int Y, int W, int H, int cx = 0, int cy = 0)
    {
        if (image_ is null)
        {
            drawEmpty(X, Y);
            return;
        }
        int width = image_.w(), height = image_.h();
        image_.scale(w(), h(), false, true);
        image_.draw(X, Y, W, H, cx, cy);
        image_.scale(width, height, false, true);
    }

    override void uncache()
    {
        if (image_ !is null) image_.uncache();
    }

    /// The wrapped image -- inspect or `.copy()` it if needed, but
    /// never mutate it directly (matches FLTK's own documented
    /// caution: modifying it in place would corrupt every other
    /// caller sharing this same cached image).
    inout(Image) image() inout { return image_; }

    /**
     * Finds a shared image by name and size. If W is 0, finds the
     * *original* image with this name regardless of its own size
     * (matching FLTK: "if W == 0 and the image exists with
     * another size, then the original image with that name is
     * returned"). Bumps the refcount of whatever it finds; release()
     * it when done. Returns null if not found.
     */
    static SharedImage find(string name, int W = 0, int H = 0)
    {
        foreach (im; images_)
        {
            bool matches = im.name_ == name
                && (W == 0 ? im.original_ : (im.dataW() == W && im.dataH() == H));
            if (matches)
            {
                im.refcount_++;
                return im;
            }
        }
        return null;
    }

    /**
     * Finds or loads a shared image by filename, optionally resized
     * to W x H. If the exact size is already cached, returns it
     * (refcount bumped). If only the original size is cached (or
     * nothing is), loads/finds the original, and -- if a different
     * size was requested -- creates and caches a resized copy too (the
     * original is *not* replaced, so a later request for a different
     * size again starts from the original, matching FLTK's own
     * "two images cached" note). Returns null if the file can't be
     * loaded/recognized. release() the result when done.
     */
    static SharedImage get(string name, int W = 0, int H = 0)
    {
        auto temp = find(name, W, H);
        if (temp !is null) return temp;

        bool tempReferenced = false;
        temp = find(name);
        if (temp !is null)
        {
            tempReferenced = true;
        }
        else
        {
            temp = new SharedImage(name);
            if (temp.image_ is null) return null;
            temp.add();
        }

        if ((temp.w() != W || temp.h() != H) && W != 0 && H != 0)
        {
            auto newTemp = temp.copyImpl(W, H);
            if (!tempReferenced) temp.refcount_++;
            newTemp.add();
            return newTemp;
        }
        return temp;
    }

    /// Wraps an already-in-memory RGBImage as a shared image under a
    /// synthetic unique name (a random UUID, matching FLTK's own
    /// `Fl_Preferences::newUUID()` -- `std.uuid.randomUUID()` here,
    /// no need to route through `fl.preferences` for this). If ownIt,
    /// rgb is deleted when the shared image is; otherwise the caller
    /// keeps owning it.
    static SharedImage getFromRgb(RGBImage rgb, bool ownIt = true)
    {
        import std.uuid : randomUUID;

        auto shared_ = new SharedImage(randomUUID().toString(), rgb);
        shared_.allocImage_ = ownIt;
        shared_.add();
        return shared_;
    }

    /// The full pool of currently-cached shared images (every size of
    /// every name, not just originals).
    static const(SharedImage)[] images() { return images_; }

    /// ditto, just the count.
    static int numImages() { return cast(int) images_.length; }

    /// Registers a format-detection handler for files this port's own
    /// built-in XBM/XPM/PNM sniffing doesn't recognize -- tried, in
    /// registration order, whenever reload() falls through to the
    /// handler chain. A no-op if f is already registered.
    static void addHandler(SharedHandler f)
    {
        foreach (h; handlers_)
            if (h == f) return;
        handlers_ ~= f;
    }

    /// Unregisters a handler added with addHandler().
    static void removeHandler(SharedHandler f)
    {
        foreach (i, h; handlers_)
        {
            if (h == f)
            {
                handlers_ = handlers_[0 .. i] ~ handlers_[i + 1 .. $];
                return;
            }
        }
    }

    /// package(fl): test-only reset of every bit of shared static
    /// state this module tracks, matching CONVENTIONS.md's "shared static
    /// state needs hermetic tests" convention (same reasoning as
    /// fl.core.resetForTest()/fl.group's FlGroup.current(null) advice) --
    /// every test in this module leaves the pool/handler-chain empty
    /// again afterward so later tests (in this module or others) don't
    /// see leftover images from an earlier one.
    package(fl) static void resetForTest()
    {
        images_ = null;
        handlers_ = null;
    }
}

/// Header-sniffing handler for the natively-decodable formats this port
/// has that (unlike XBM/XPM/PNM above) aren't hardcoded directly into
/// `reload()` -- matches FLTK's own choice to keep these behind the
/// same pluggable `add_handler()` chain rather than hardcoding them too
/// (`fl_images_core.cxx`'s own `fl_check_images()`, which this is a
/// ported reduction of). None of GIF/SVG/PNG/JPEG link an
/// external codec in this port (see CONVENTIONS.md's "Correction"
/// note for GIF/SVG; `fl.png_image`'s/`fl.jpeg_image`'s
/// own module comments for PNG/JPEG -- both adapted from already-D
/// `arsd.png`/`arsd.jpeg` rather than bound to libpng/libjpeg).
/// Checked in FLTK's own order: GIF, BMP, ICO, PNG, JPEG, SVG.
private Image checkNativeFormats(string name, const(ubyte)[] header)
{
    import fl.bmp_image : BMPImage;
    import fl.ico_image : ICOImage;
    import fl.gif_image : GifImage;
    import fl.anim_gif_image : AnimGifImage;
    import fl.png_image : PngImage;
    import fl.jpeg_image : JpegImage;
    import fl.svg_image : SvgImage;

    if (header.length < 6) return null;

    if ((header[0 .. 6] == "GIF87a") || (header[0 .. 6] == "GIF89a"))
        return GifImage.animate ? cast(Image) new AnimGifImage(name) : cast(Image) new GifImage(name);

    if (header[0] == 'B' && header[1] == 'M')
    {
        // Check the bits-per-pixel too, so a text file starting with "BM"
        // isn't taken for a BMP.
        uint biSize = header.length >= 18
            ? header[14] | (header[15] << 8) | (header[16] << 16) | (cast(uint) header[17] << 24) : 0;
        uint bitCount = 0;
        if (biSize >= 40 && header.length >= 30) bitCount = header[28] | (header[29] << 8);
        else if (biSize >= 12 && header.length >= 26) bitCount = header[24] | (header[25] << 8);
        if (bitCount == 1 || bitCount == 4 || bitCount == 8
            || bitCount == 16 || bitCount == 24 || bitCount == 32)
            return new BMPImage(name);
    }
    if (header[0] == 0 && header[1] == 0 && header[2] == 1 && header[3] == 0 && header[5] == 0)
        return new ICOImage(name);

    if (header[0] == 0x89 && header[1] == 'P' && header[2] == 'N' && header[3] == 'G')
        return new PngImage(name);

    // JPEG/JFIF: FFD8FF, followed by an APPn/marker byte in [0xC0,0xFE]
    // (matching FLTK's own detection exactly).
    if (header[0] == 0xff && header[1] == 0xd8 && header[2] == 0xff
        && header[3] >= 0xc0 && header[3] <= 0xfe)
        return new JpegImage(name);

    // SVG, plain or gzip'd (`.svgz`) -- `fl.svg_image.SvgImage` itself
    // decompresses gzip input now (see that module's own top comment),
    // so a gzip-magic-prefixed file is a plausible `.svgz` candidate
    // without needing to pre-decompress the (already-truncated, 64-byte)
    // `header` buffer here just to sniff the real signature the way
    // FLTK's own `fl_check_images()` does (`gzdopen()`/`gzread()`
    // on a fresh file handle, decompressing just enough to confirm
    // `<?xml`/`<svg`/`<!--`) -- `SvgImage`'s own `w() && h()` success
    // check below already rejects a gzip file that isn't actually SVG,
    // same net effect via the constructor's own real decompress-then-
    // parse attempt rather than a separate pre-check.
    if (header.length > 2 && header[0] == 0x1f && header[1] == 0x8b)
    {
        auto image = new SvgImage(name);
        if (image.w() && image.h()) return image;
    }

    {
        import std.ascii : isWhite;

        const(ubyte)[] buf = header;
        // UTF-8 BOM, if present (FLTK's own issue #247 handling).
        if (buf.length >= 3 && buf[0] == 0xef && buf[1] == 0xbb && buf[2] == 0xbf)
            buf = buf[3 .. $];
        while (buf.length && isWhite(cast(char) buf[0])) buf = buf[1 .. $];
        if ((buf.length >= 5 && buf[0 .. 5] == "<?xml")
            || (buf.length >= 4 && buf[0 .. 4] == "<svg")
            || (buf.length >= 4 && buf[0 .. 4] == "<!--"))
        {
            auto image = new SvgImage(name);
            if (image.w() && image.h()) return image;
        }
    }

    return null;
}

/**
 * Ported from `fl_register_images()` (`FL/Fl_Shared_Image.H` +
 * `src/fl_images_core.cxx`). Registers `checkNativeFormats()` above into
 * `SharedImage`'s `addHandler()` chain, so `SharedImage.get()`/
 * `reload()` can recognize `.gif`/`.bmp`/`.ico`/`.svg`/`.png`/`.jpg`
 * files it otherwise falls through on, matching FLTK's own
 * `fl_check_images()` handler -- every format FLTK's own handler
 * covers is a real, native decoder here too, none deferred. A no-op if
 * already called (`addHandler()`'s
 * own dedup).
 *
 * **Not load-bearing for clipboard image paste** in this port --
 * `fl.platform_x11`'s `SelectionNotify` handler decodes a pasted BMP
 * directly via `new BMPImage("clipboard", data)`, bypassing
 * `SharedImage`/this handler chain entirely (no temp file, unlike
 * FLTK's own `mkstemp()` + `Fl_Shared_Image::get()` approach for
 * the same step). Calling this is still worth doing for API fidelity
 * (matching every real FLTK program's own `fl_register_images()`
 * call, e.g. `source/test/clipboard.d`'s), and for its *other* real
 * effect -- any plain `SharedImage.get("some.gif")`/`get("some.bmp")`/
 * `get("some.ico")`/`get("some.svg")` call elsewhere in an app now
 * actually finds those files -- just don't assume it's on the
 * clipboard-paste code path if tracing through that feature later.
 *
 * **This is what `fl.help_view.HelpView`'s `<IMG>` tag loading goes
 * through** (via `SharedImage.get()`) -- a program that never calls
 * this silently
 * shows no image at all for a referenced `.gif`/`.svg`/etc. file, not
 * an error, since `reload()` just falls through every detection branch
 * with nothing registered.
 */
void registerImages()
{
    import std.functional : toDelegate;

    SharedImage.addHandler(toDelegate(&checkNativeFormats));
}

unittest
{
    // get()/find()/release(): the core caching/refcounting contract,
    // using getFromRgb() so this stays headless (no real file needed).
    SharedImage.resetForTest();
    scope (exit) SharedImage.resetForTest();

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto rgb = new RGBImage(bits, 2, 2, 3);
    auto shared_ = SharedImage.getFromRgb(rgb);
    string name = shared_.name();

    assert(shared_.refcount() == 1);
    assert(shared_.original());
    assert(shared_.w() == 2 && shared_.h() == 2);
    assert(SharedImage.numImages() == 1);

    auto found = SharedImage.find(name);
    assert(found is shared_);
    assert(shared_.refcount() == 2); // find() bumped it

    found.release();
    assert(shared_.refcount() == 1);

    shared_.release(); // drops to 0 -- removed from the pool
    assert(SharedImage.numImages() == 0);
}

unittest
{
    // get(name, W, H): requesting a different size caches a *second*
    // entry (the resized copy) alongside the untouched original.
    SharedImage.resetForTest();
    scope (exit) SharedImage.resetForTest();

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto rgb = new RGBImage(bits, 2, 2, 3);
    auto original = SharedImage.getFromRgb(rgb);
    string name = original.name();

    auto resized = SharedImage.get(name, 20, 20);
    assert(resized !is null);
    assert(resized.w() == 20 && resized.h() == 20);
    assert(!resized.original());
    assert(SharedImage.numImages() == 2); // original + resized copy

    // Requesting the same size again finds the cached resized copy,
    // not a third one.
    auto resizedAgain = SharedImage.get(name, 20, 20);
    assert(resizedAgain is resized);
    assert(SharedImage.numImages() == 2);

    resizedAgain.release();
    resized.release();
    original.release();
}

unittest
{
    // retain(): bumps refcount and returns the same object, distinct
    // from copy(W,H)'s real-resize behavior.
    SharedImage.resetForTest();
    scope (exit) SharedImage.resetForTest();

    ubyte[] bits = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0];
    auto rgb = new RGBImage(bits, 2, 2, 3);
    auto shared_ = SharedImage.getFromRgb(rgb);

    auto same = shared_.retain();
    assert(same is shared_);
    assert(shared_.refcount() == 2);

    auto resized = shared_.copy(20, 20);
    assert(resized !is shared_);
    assert((cast(SharedImage) resized).w() == 20);

    same.release();
    shared_.release();
    (cast(SharedImage) resized).release();
}

unittest
{
    // addHandler()/removeHandler(): a real end-to-end handler round
    // trip via a temp file with an unrecognized (to the built-in
    // XBM/XPM/PNM sniffing) header.
    import std.file : write, remove, tempDir, exists;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    SharedImage.resetForTest();
    scope (exit) SharedImage.resetForTest();

    auto path = buildPath(tempDir(), "fldtk-shared-test-" ~ randomUUID().toString() ~ ".myfmt");
    scope (exit) if (exists(path)) remove(path);
    write(path, "MYFORMAT1\nsome data\n");

    int calls;
    Image handler(string name, const(ubyte)[] header)
    {
        calls++;
        if (header.length >= 9 && cast(string) header[0 .. 9] == "MYFORMAT1")
            return new RGBImage([1, 2, 3], 1, 1, 3);
        return null;
    }

    SharedImage.addHandler(&handler);
    scope (exit) SharedImage.removeHandler(&handler);

    auto shared_ = SharedImage.get(path);
    assert(shared_ !is null);
    assert(calls == 1);
    assert(shared_.w() == 1 && shared_.h() == 1);
    shared_.release();

    SharedImage.removeHandler(&handler);
    calls = 0;
    auto notFound = SharedImage.get(path);
    assert(notFound is null); // handler no longer registered
}

unittest
{
    // A missing file fails cleanly (get() returns null), and doesn't
    // leave a half-constructed entry in the pool.
    SharedImage.resetForTest();
    scope (exit) SharedImage.resetForTest();

    auto missing = SharedImage.get("/nonexistent/path/does-not-exist.png");
    assert(missing is null);
    assert(SharedImage.numImages() == 0);
}
