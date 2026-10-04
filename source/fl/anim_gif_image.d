/*
 * Ported from FL/Fl_Anim_GIF_Image.H + src/Fl_Anim_GIF_Image.cxx
 * (FLTK 1.5.0, ~/Repositories/fltk): Fl_Anim_GIF_Image, animated-GIF
 * loading/playback. No external library needed, same as fl.gif_image
 * (see that module's own top comment).
 *
 * `AnimGifImage` extends `fl.gif_image.GifImage`, overriding its
 * `onFrameData()`/`onExtensionData()` hooks -- there is only ever one
 * GIF parser in this port, matching FLTK's own `Fl_Anim_GIF_Image :
 * public Fl_GIF_Image` relationship exactly. `onFrameData()` composites
 * each decoded frame into a persistent, canvas-sized `offscreen_`
 * buffer (handling the GIF disposal-method spec: `not`/`background`/
 * `previous`) and stores either the full composited canvas (default)
 * or just the frame's own encoded sub-rectangle (`optimizeMemory`
 * flag) as a real `fl.image.RGBImage`.
 *
 * FLTK splits this into two classes (`Fl_Anim_GIF_Image` + a
 * private `FrameInfo` helper, `friend`-accessed) purely for its own
 * C++ header-hiding convention -- collapsed into one class here, no
 * functional difference.
 *
 * Deliberate simplifications vs. FLTK:
 *  - No `Fl_Shared_Image`-backed "scalable" cache for `scale_frame()`.
 *    `fl.image.Image.scale()` is already lazy/metadata-only (the real
 *    resample happens inside `RGBImage.draw()`'s own cached path at
 *    draw time) -- FLTK's own `scale_frame()` calls are pre-
 *    emptive consistency nudges, not a real resampling step, so this
 *    port just calls `.scale()` right before each frame is drawn
 *    instead of tracking a second cached/scaled copy.
 *  - No `Fl_Graphics_Driver::default_driver().scale()` HiDPI multiplier
 *    in the `optimizeMemory` draw loop -- this port has no per-driver
 *    scale factor anywhere else either (a documented, existing
 *    simplification, not new to this module).
 *  - `Fl_Anim_GIF_Image::frame_count()`/`is_animated()` (static +
 *    instance) are not ported -- no sample exercises either, and both
 *    are pure conveniences over `frames()`/`valid()`, easy to add
 *    later if a real caller needs them.
 *  - `Fl::warning()`/`Fl::error()` diagnostic calls are dropped, not
 *    translated to `stderr` output -- matches this port's established
 *    "no Fl::warning()/Fl::error() equivalent" convention (see e.g.
 *    `fl.core`'s and `fl.draw`'s own notes on the same gap); none of
 *    them affect `fail()`/`ld()`, which still report failure
 *    correctly.
 *
 * Faithfully ported, not fixed, despite looking questionable on a
 * close read (matching CLAUDE.md's "port faithfully, note the
 * quirk, don't silently correct it" policy):
 *  - `onFrameData()`'s `transparentColorIndex` uses a *truthy* check on
 *    the raw transparent-pixel index (`gf.trans != 0 && ...`), not
 *    `gf.trans >= 0` -- when the transparent color is index 0, this
 *    frame's `transparentColorIndex` silently becomes -1 (only affects
 *    `disposeFrame()`'s background-color choice; the actual per-pixel
 *    transparency check during compositing, `c == gf.trans`, is
 *    unaffected and stays correct even for index 0).
 *  - `disposeFrame()`'s `previous`-disposal copy uses the *previous*
 *    frame's own encoded width as its source stride even when frames
 *    are stored full-canvas-sized (`optimizeMemory` off) -- correct
 *    only when that previous frame happened to cover the whole canvas;
 *    a real, if narrow (disposal chain + a genuinely partial ancestor
 *    frame), latent bug inherited from FLTK.
 */
module fl.anim_gif_image;

import fl.gif_image : GifImage;
import fl.image : Image, RGBImage;
import fl.widget : Widget;
import fl.enumerations : Color;
static import fl.enumerations;
static import fl.core;

class AnimGifImage : GifImage
{
    enum ushort dontStart = 1;
    enum ushort dontResizeCanvas = 2;
    enum ushort dontSetAsImage = 4;
    enum ushort optimizeMemory = 8;
    enum ushort logFlag = 64;
    enum ushort debugFlag = 128;

    /// Ported from `Fl_Anim_GIF_Image::min_delay`.
    static double minDelay = 0.0;
    /// Ported from `Fl_Anim_GIF_Image::loop`.
    static bool loop = true;

    private enum Dispose
    {
        undef = 0,
        not = 1,
        background = 2,
        previous = 3,
    }

    // "no transparency"/opaque vs. "fully transparent" alpha sentinels
    // -- ported from FrameInfo::Transparency (T_NONE/T_FULL); the
    // names read backwards at a glance but mean exactly what they say
    // ("no [applied] transparency" = opaque, "full transparency").
    private enum ubyte tNone = 0xff;
    private enum ubyte tFull = 0;

    private struct AnimFrame
    {
        RGBImage rgb;
        Color averageColor = fl.enumerations.black;
        float averageWeight = -1;
        bool desaturated;
        int x, y, w, h; // this frame's own encoded rectangle
        double delay; // seconds
        Dispose dispose;
        int transparentColorIndex = -1;
        ubyte[4] transparentColor;
    }

    private string name_;
    private ushort flags_;
    private Widget canvas_;
    private bool uncacheFlag_;
    private bool valid_;
    private int frame_ = -1;
    private double speed_ = 1.0;

    private AnimFrame[] frames_;
    private int loopCount_ = 1;
    private int loopCur_ = 0;
    private int backgroundColorIndex_ = -1;
    private ubyte[4] backgroundColor_;
    private int canvasW_, canvasH_;
    private bool desaturatePending_;
    private Color averageColor_;
    private float averageWeight_ = -1;
    private bool optimizeMem_;
    private int debugLevel_;
    private ubyte[] offscreen_;

    /// Ported from the file-loading constructor.
    this(string filename, Widget canvas = null, ushort flags = 0)
    {
        super();
        setupFlags(flags);
        valid_ = loadAnim(filename, null, 0);
        adoptCanvasSize();
        this.canvas(canvas, flags);
        if (!(flags & dontStart)) start();
        else frame_ = 0;
    }

    /// Ported from the in-memory-buffer-loading constructor. `length`
    /// is accepted (matching FLTK's own signature and this
    /// class's real callers) even though a D slice already carries its
    /// own length.
    this(string imagename, const(ubyte)[] data, size_t length, Widget canvas = null, ushort flags = 0)
    {
        super();
        setupFlags(flags);
        auto sliced = length <= data.length ? data[0 .. length] : data;
        valid_ = loadAnim(imagename, sliced, sliced.length);
        adoptCanvasSize();
        this.canvas(canvas, flags);
        if (!(flags & dontStart)) start();
        else frame_ = 0;
    }

    /// Ported from `Fl_Anim_GIF_Image()` -- an empty shell.
    this()
    {
        super();
    }

    ~this()
    {
        // removeTimeout() reaches into fl.core's module-level timer
        // queue -- other-object work that's only safe when this
        // destructor runs deterministically (explicit destroy()).
        // During GC-driven finalization the collection order is
        // undefined, so skip it there -- matches CLAUDE.md's own
        // documented GC-finalizer-hazard pattern (a real SIGSEGV
        // during rt_finalizeFromGC was hit once elsewhere in this
        // port from the exact same shape of bug).
        import core.memory : GC;

        if (!GC.inFinalizer())
            fl.core.removeTimeout(&cbAnimate);
    }

    private void setupFlags(ushort flags)
    {
        flags_ = flags;
        debugLevel_ = ((flags & logFlag) != 0 ? 1 : 0) + ((flags & debugFlag) != 0 ? 2 : 0);
        optimizeMem_ = (flags & optimizeMemory) != 0;
    }

    private void adoptCanvasSize()
    {
        if (canvasW_ && canvasH_ && w() == 0 && h() == 0)
        {
            w(canvasW_);
            h(canvasH_);
        }
    }

    // -- file handling --------------------------------------------------

    protected alias load = GifImage.load; // re-expose the protected overload set the method below hides

    /// Ported from `Fl_Anim_GIF_Image::load()`.
    bool load(string name, const(ubyte)[] imgdata = null, size_t imglength = 0)
    {
        return loadAnim(name, imgdata, imglength);
    }

    bool valid() const
    {
        return valid_;
    }

    private bool loadAnim(string name, const(ubyte)[] imgdata, size_t imglength)
    {
        clearFrames();
        name_ = name;

        // Replicate what re-loading needs to reset (mirrors FLTK's
        // own manual replication of the Fl_Pixmap destructor's job,
        // since load() can be called more than once on the same
        // object).
        uncache();
        xpmData = null;
        w(0);
        h(0);

        if (name.length || imgdata !is null)
        {
            if (imgdata !is null)
                super.load(name, imgdata, true); // GifImage.load(), anim=true
            else
                super.load(name, true);
        }

        frame_ = cast(int) frames_.length - 1;
        valid_ = frames_.length > 0;

        if (!valid_)
            ld(errFormat); // matches FLTK: unconditionally ERR_FORMAT,
        // even for what was really a file-access failure -- see this
        // module's own top comment.

        return valid_;
    }

    // -- getters and setters --------------------------------------------

    void frameUncache(bool uncache)
    {
        uncacheFlag_ = uncache;
    }

    bool frameUncache() const
    {
        return uncacheFlag_;
    }

    double delay(int frame) const
    {
        if (frame >= 0 && frame < frames()) return frames_[frame].delay;
        return 0.0;
    }

    void delay(int frame, double delay)
    {
        if (frame >= 0 && frame < frames()) frames_[frame].delay = delay;
    }

    /// Ported from `Fl_Anim_GIF_Image::canvas()`.
    void canvas(Widget canvas, ushort flags = 0)
    {
        if (canvas_) canvas_.image(null);
        canvas_ = canvas;
        if (canvas_ && !(flags & dontSetAsImage)) canvas_.image(this);
        if (canvas_ && !(flags & dontResizeCanvas)) canvas_.size(w(), h());
        if (flags_ != flags)
        {
            flags_ = flags;
            debugLevel_ = ((flags & logFlag) != 0 ? 1 : 0) + ((flags & debugFlag) != 0 ? 2 : 0);
        }
        frame_ = -1;
        if (fl.core.hasTimeout(&cbAnimate))
        {
            fl.core.removeTimeout(&cbAnimate);
            nextFrame();
        }
        else if (frames_.length)
        {
            setCurrentFrame(0);
        }
    }

    inout(Widget) canvas() inout
    {
        return canvas_;
    }

    int canvasW() const
    {
        return canvasW_;
    }

    int canvasH() const
    {
        return canvasH_;
    }

    string name() const
    {
        return name_;
    }

    void speed(double speed)
    {
        speed_ = speed;
    }

    double speed() const
    {
        return speed_;
    }

    // -- animation --------------------------------------------------

    int frames() const
    {
        return cast(int) frames_.length;
    }

    void frame(int frame)
    {
        if (fl.core.hasTimeout(&cbAnimate)) return; // "not idle" -- see top comment on dropped warnings
        if (frame >= 0 && frame < frames()) setCurrentFrame(frame);
    }

    int frame() const
    {
        return frame_;
    }

    Image image() const
    {
        return frame_ >= 0 && frame_ < frames() ? cast(Image) frames_[frame_].rgb : null;
    }

    Image image(int frame) const
    {
        if (frame >= 0 && frame < frames()) return cast(Image) frames_[frame].rgb;
        return null;
    }

    bool start()
    {
        fl.core.removeTimeout(&cbAnimate);
        if (frames_.length) nextFrame();
        return frames_.length != 0;
    }

    bool stop()
    {
        fl.core.removeTimeout(&cbAnimate);
        return frames_.length != 0;
    }

    bool next()
    {
        if (frames_.length && !fl.core.hasTimeout(&cbAnimate))
        {
            int f = frame() + 1;
            if (f >= frames()) f = 0;
            frame(f);
        }
        return frames_.length != 0;
    }

    bool playing()
    {
        return valid() && fl.core.hasTimeout(&cbAnimate);
    }

    // -- image data --------------------------------------------------

    AnimGifImage resize(int newW, int newH)
    {
        int W = newW, H = newH;
        if (canvas_ && !W && !H)
        {
            W = canvas_.w();
            H = canvas_.h();
        }
        if (!W || !H || (W == this.w() && H == this.h())) return this;

        double sfx = cast(double) W / canvasW_;
        double sfy = cast(double) H / canvasH_;
        if (optimizeMem_)
        {
            foreach (ref f; frames_)
            {
                f.x = cast(int) lround(f.x * sfx);
                f.y = cast(int) lround(f.y * sfy);
                f.w = cast(int) lround(f.w * sfx);
                f.h = cast(int) lround(f.h * sfy);
            }
        }
        canvasW_ = W;
        canvasH_ = H;
        this.w(canvasW_);
        this.h(canvasH_);
        if (canvas_ && !(flags_ & dontResizeCanvas)) canvas_.size(this.w(), this.h());
        return this;
    }

    AnimGifImage resize(double scale)
    {
        return resize(cast(int) lround(w() * scale), cast(int) lround(h() * scale));
    }

    int frameX(int frame) const
    {
        if (frame >= 0 && frame < frames()) return frames_[frame].x;
        return -1;
    }

    int frameY(int frame) const
    {
        if (frame >= 0 && frame < frames()) return frames_[frame].y;
        return -1;
    }

    int frameW(int frame) const
    {
        if (frame >= 0 && frame < frames()) return frames_[frame].w;
        return -1;
    }

    int frameH(int frame) const
    {
        if (frame >= 0 && frame < frames()) return frames_[frame].h;
        return -1;
    }

    // -- overridden methods --------------------------------------------

    override void colorAverage(Color c, float i)
    {
        if (i < 0)
        {
            i = -i;
            foreach (ref f; frames_) f.rgb.colorAverage(c, i);
            return;
        }
        averageColor_ = c;
        averageWeight_ = i;
        // Deliberately not calling applyFrameEdits() here -- matches
        // FLTK's own comment: doing so before the display
        // connection is open could average *this* frame with a
        // different RGB value than the following frames.
    }

    alias copy = Image.copy; // re-expose the 0-arg overload the override below hides

    override AnimGifImage copy(int W, int H) const
    {
        auto copied = new AnimGifImage();
        if (frames_.length)
        {
            // GifImage doesn't override copy(int,int) -- this resolves
            // to the inherited Pixmap.copy(int,int), resizing the
            // frame-0 XPM data without recursing back into this
            // override.
            auto gif = super.copy(W, H);
            copied.xpmData = gif.xpmData;
        }

        copied.name_ = name_;
        copied.flags_ = flags_;
        copied.frame_ = frame_;
        copied.speed_ = speed_;

        copied.w(W);
        copied.h(H);
        copied.canvasW_ = W;
        copied.canvasH_ = H;
        copied.copyFramesFrom(this);

        copied.uncacheFlag_ = uncacheFlag_;
        copied.valid_ = valid_ && copied.frames_.length == frames_.length;
        if (copied.valid_ && frame_ >= 0 && !fl.core.hasTimeout(&copied.cbAnimate))
            copied.start();
        return copied;
    }

    private void copyFramesFrom(const AnimGifImage src)
    {
        double sfx = cast(double) canvasW_ / src.canvasW_;
        double sfy = cast(double) canvasH_ / src.canvasH_;
        foreach (i, ref sf; src.frames_)
        {
            AnimFrame f = cast(AnimFrame) sf; // struct copy
            if (src.optimizeMem_)
            {
                f.x = cast(int) lround(sf.x * sfx);
                f.y = cast(int) lround(sf.y * sfy);
                f.w = cast(int) lround(sf.w * sfx);
                f.h = cast(int) lround(sf.h * sfy);
            }
            f.rgb = cast(RGBImage) sf.rgb.copy(); // same size -- real resizing happens lazily at draw time
            frames_ ~= f;
        }
        optimizeMem_ = src.optimizeMem_;
        loopCount_ = src.loopCount_;
    }

    override void desaturate()
    {
        desaturatePending_ = true;
        applyFrameEdits();
    }

    override void draw(int x, int y, int w, int h, int cx = 0, int cy = 0)
    {
        auto img = image();
        if (img is null)
        {
            super.draw(x, y, w, h, cx, cy); // fall back to the static Pixmap draw
            return;
        }

        if (optimizeMem_)
        {
            int f0 = frame_;
            while (f0 > 0
                && !(frames_[f0].x == 0 && frames_[f0].y == 0
                    && frames_[f0].w == this.w() && frames_[f0].h == this.h()))
                f0--;
            foreach (f; f0 .. frame_ + 1)
            {
                if (f < frame_ && frames_[f].dispose == Dispose.previous) continue;
                if (f < frame_ && frames_[f].dispose == Dispose.background) continue;
                auto rgb = frames_[f].rgb;
                if (rgb !is null)
                {
                    rgb.scale(frames_[f].w, frames_[f].h, false, true);
                    rgb.draw(x + frames_[f].x, y + frames_[f].y, w, h, cx, cy);
                }
            }
        }
        else
        {
            img.scale(this.w(), this.h(), false, true);
            img.draw(x, y, w, h, cx, cy);
        }
    }

    alias draw = Image.draw; // re-expose the 2-arg overload the override above hides

    override void uncache()
    {
        super.uncache();
        // Same GC-finalizer hazard as ~this() above: f.rgb.uncache() is
        // a virtual call into another GC-managed object, only safe when
        // collection order is guaranteed (deterministic destroy()), not
        // during GC-driven finalization at program exit. Pixmap.~this()
        // calls uncache() and D does not unwind the vtable during
        // destruction (see CLAUDE.md), so this override is reachable
        // from finalization even though the guard lives one level up.
        import core.memory : GC;

        if (GC.inFinalizer())
            return;
        foreach (ref f; frames_)
            if (f.rgb) f.rgb.uncache();
    }

    // -- protected/private implementation --------------------------------------------

    private void clearFrames()
    {
        frames_ = null;
        offscreen_ = null;
        valid_ = false;
    }

    /// Ported from `FrameInfo::convert_delay()`.
    private double convertDelay(int d) const
    {
        if (d <= 0) d = loopCount_ != 1 ? 10 : 0;
        return cast(double) d / 100;
    }

    override protected void onFrameData(ref GifFrame gf)
    {
        if (gf.bptr.length == 0) return;
        int delayRaw = gf.delay;
        if (delayRaw <= 0) delayRaw = -(delayRaw + 1);

        if (gf.ifrm == 0)
        {
            canvasW_ = gf.width;
            canvasH_ = gf.height;
            offscreen_ = new ubyte[canvasW_ * canvasH_ * 4]; // zero-initialized by `new`

            backgroundColorIndex_ = (gf.clrs && gf.bkgd < gf.clrs) ? gf.bkgd : -1;
            if (backgroundColorIndex_ >= 0)
            {
                auto c = gf.cpal[backgroundColorIndex_];
                backgroundColor_ = [c.r, c.g, c.b, tNone];
            }
        }

        AnimFrame frame;
        frame.x = gf.x;
        frame.y = gf.y;
        frame.w = gf.w;
        frame.h = gf.h;
        frame.delay = convertDelay(delayRaw);
        // Faithful truthy check, not `gf.trans >= 0` -- see this
        // module's top comment.
        frame.transparentColorIndex = (gf.trans != 0 && gf.trans < gf.clrs) ? gf.trans : -1;
        frame.dispose = cast(Dispose) gf.dispose;
        if (frame.transparentColorIndex >= 0)
        {
            auto c = gf.cpal[frame.transparentColorIndex];
            frame.transparentColor = [c.r, c.g, c.b, tFull];
        }

        disposeFrame(cast(int) frames_.length - 1);

        const(ubyte)[] bits = gf.bptr;
        size_t bitsIdx = 0;
        size_t endOff = cast(size_t) canvasW_ * canvasH_ * 4;
        foreach (y; frame.y .. frame.y + frame.h)
        {
            foreach (x; frame.x .. frame.x + frame.w)
            {
                ubyte c = bits[bitsIdx++];
                if (c == gf.trans) continue;
                size_t off = cast(size_t) y * canvasW_ * 4 + cast(size_t) x * 4;
                if (off >= endOff) continue;
                if (c >= gf.cpal.length) continue;
                offscreen_[off] = gf.cpal[c].r;
                offscreen_[off + 1] = gf.cpal[c].g;
                offscreen_[off + 2] = gf.cpal[c].b;
                offscreen_[off + 3] = tNone;
            }
        }

        ubyte[] buf;
        int rw, rh;
        if (optimizeMem_)
        {
            buf = new ubyte[frame.w * frame.h * 4];
            size_t dst = 0;
            foreach (y; frame.y .. frame.y + frame.h)
            {
                foreach (x; frame.x .. frame.x + frame.w)
                {
                    size_t off = cast(size_t) y * canvasW_ * 4 + cast(size_t) x * 4;
                    if (off < endOff) buf[dst .. dst + 4] = offscreen_[off .. off + 4];
                    dst += 4;
                }
            }
            rw = frame.w;
            rh = frame.h;
        }
        else
        {
            buf = offscreen_.dup;
            rw = canvasW_;
            rh = canvasH_;
        }
        frame.rgb = new RGBImage(buf, rw, rh, 4);

        frames_ ~= frame;
    }

    override protected void onExtensionData(ref GifFrame gf)
    {
        if (gf.bptr.length < 11) return;
        if (gf.bptr[0 .. 11] == "NETSCAPE2.0" && gf.bptr.length >= 14)
        {
            loopCount_ = gf.bptr[12] | (gf.bptr[13] << 8);
        }
    }

    /// Ported from `FrameInfo::dispose()`.
    private void disposeFrame(int frame)
    {
        if (frame < 0) return;
        final switch (frames_[frame].dispose)
        {
        case Dispose.previous:
            int prev = frame;
            while (prev > 0 && frames_[prev].dispose == Dispose.previous) prev--;
            if (prev == 0 && frames_[prev].dispose == Dispose.previous)
            {
                setToBackground(frame);
                return;
            }
            {
                auto src = frames_[prev].rgb.array;
                int px = frames_[prev].x, py = frames_[prev].y;
                int pw = frames_[prev].w, ph = frames_[prev].h;
                if (px == 0 && py == 0 && pw == canvasW_ && ph == canvasH_)
                {
                    offscreen_[0 .. canvasW_ * canvasH_ * 4] = src[0 .. canvasW_ * canvasH_ * 4];
                }
                else
                {
                    if (px + pw > canvasW_) pw = canvasW_ - px;
                    if (py + ph > canvasH_) ph = canvasH_ - py;
                    foreach (y; 0 .. ph)
                    {
                        size_t dstOff = cast(size_t)(y + py) * canvasW_ * 4 + cast(size_t) px * 4;
                        size_t srcOff = cast(size_t) y * frames_[prev].w * 4;
                        if (dstOff + pw * 4 <= offscreen_.length && srcOff + pw * 4 <= src.length)
                            offscreen_[dstOff .. dstOff + pw * 4] = src[srcOff .. srcOff + pw * 4];
                    }
                }
            }
            break;

        case Dispose.background:
            setToBackground(frame);
            break;

        case Dispose.not:
        case Dispose.undef:
            break; // keep everything as is
        }
    }

    /// Ported from `FrameInfo::set_to_background()`.
    private void setToBackground(int frame)
    {
        int bg = backgroundColorIndex_;
        int tp = frame >= 0 ? frames_[frame].transparentColorIndex : bg;
        ubyte[4] color = frame >= 0 && tp >= 0 ? frames_[frame].transparentColor : backgroundColor_;
        if (tp >= 0 && bg >= 0) bg = tp;
        color[3] = tp == bg ? tFull : (tp < 0 ? tFull : tNone);
        for (size_t off = 0; off + 4 <= offscreen_.length; off += 4)
            offscreen_[off .. off + 4] = color[];
    }

    /// Ported from `Fl_Anim_GIF_Image::next_frame()`.
    private bool nextFrame()
    {
        int frame = frame_;
        frame++;
        if (frame >= frames_.length)
        {
            loopCur_++;
            if (loop && loopCount_ > 0 && loopCur_ > loopCount_)
            {
                stop();
                return frames_.length != 0;
            }
            else frame = 0;
        }
        if (frame >= frames_.length) return false;
        setCurrentFrame(frame);
        double d = frames_[frame].delay;
        if (minDelay && d < minDelay) d = minDelay;
        if (isAnimatedInternal() && d > 0 && speed_ > 0)
        {
            d /= speed_;
            fl.core.addTimeout(d, &cbAnimate);
        }
        return true;
    }

    private bool isAnimatedInternal() const
    {
        return valid_ && frames_.length > 1;
    }

    private void cbAnimate()
    {
        nextFrame();
    }

    /// Ported from `FrameInfo::set_frame()` -- applies any pending
    /// color-average/desaturate to the current frame's image.
    private void applyFrameEdits()
    {
        if (frame_ < 0 || frame_ >= frames_.length) return;
        auto ref_ = &frames_[frame_];
        if (averageWeight_ >= 0 && averageWeight_ < 1
            && (averageColor_ != ref_.averageColor || averageWeight_ != ref_.averageWeight))
        {
            ref_.rgb.colorAverage(averageColor_, averageWeight_);
            ref_.averageColor = averageColor_;
            ref_.averageWeight = averageWeight_;
        }
        if (desaturatePending_ && !ref_.desaturated)
        {
            ref_.rgb.desaturate();
            ref_.desaturated = true;
        }
    }

    /// Ported from `Fl_Anim_GIF_Image::set_frame(int)`.
    private void setCurrentFrame(int frame)
    {
        frame_ = frame;
        if (uncacheFlag_ && image()) image().uncache();

        applyFrameEdits();

        auto cv = canvas();
        if (cv !is null)
        {
            auto parent = cv.parent();
            bool noBg = !fl.core.boxBg(cv.box());
            bool outside = !(cv.alignment() & fl.enumerations.alignInside)
                && (cv.alignment() & fl.enumerations.alignPositionMask) != fl.enumerations.alignCenter;
            if (parent !is null && (noBg || outside))
                parent.redraw();
            else
                cv.redraw();
        }
    }
}

private long lround(double v)
{
    import std.math : round;

    return cast(long) round(v);
}

unittest
{
    // A hand-built, byte-verified 2-frame animated GIF, 4x1 canvas:
    // frame 0 covers the whole canvas ([red,green,red,green]) and is
    // marked DISPOSE_BACKGROUND; frame 1 is a genuine partial
    // sub-rectangle (x=1, w=2: [green,red]), so the composited result
    // for frame 1 directly exercises disposeFrame()/setToBackground()
    // -- pixels 0 and 3 (outside frame 1's own rectangle) must show
    // the background fill (transparent, since this GIF has no
    // per-frame transparent color of its own), while pixels 1 and 2
    // show frame 1's own opaque colors. See this module's dev notes
    // for the manual LZW bit-packing derivation (mirrors the technique
    // already verified in fl.gif_image's own unittests).
    ubyte[] gif = [
        'G', 'I', 'F', '8', '9', 'a',
        4, 0, // screen width = 4
        1, 0, // screen height = 1
        0x80, // global color table, 2 colors
        0, // background color index = 0 (red)
        0, // aspect ratio
        255, 0, 0, // color 0: red
        0, 255, 0, // color 1: green
        // Graphic Control Extension: dispose=background(2), no transparency
        0x21, 0xF9, 4, 0x08, 0, 0, 0, 0,
        // Frame 0: full canvas, pixels [0,1,0,1] (red,green,red,green)
        0x2c, 0, 0, 0, 0, 4, 0, 1, 0, 0, 2, 3, 0x44, 0x10, 0x05, 0,
        // Frame 1: x=1, w=2, pixels [1,0] (green,red)
        0x2c, 1, 0, 0, 0, 2, 0, 1, 0, 0, 2, 2, 0x0C, 0x0A, 0,
        0x3b,
    ];

    auto anim = new AnimGifImage("mem", gif, gif.length);
    assert(anim.valid());
    assert(anim.frames() == 2);
    assert(anim.canvasW() == 4 && anim.canvasH() == 1);
    assert(anim.frameX(1) == 1 && anim.frameW(1) == 2 && anim.frameH(1) == 1);
    assert(anim.delay(0) == 0.0 && anim.delay(1) == 0.0);

    auto f0 = cast(RGBImage) anim.image(0);
    assert(f0 !is null);
    assert(f0.w() == 4 && f0.h() == 1 && f0.d() == 4);
    assert(f0.array[0 .. 4] == [255, 0, 0, 255]); // red, opaque
    assert(f0.array[4 .. 8] == [0, 255, 0, 255]); // green, opaque
    assert(f0.array[8 .. 12] == [255, 0, 0, 255]); // red, opaque
    assert(f0.array[12 .. 16] == [0, 255, 0, 255]); // green, opaque

    auto f1 = cast(RGBImage) anim.image(1);
    assert(f1 !is null);
    assert(f1.w() == 4 && f1.h() == 1 && f1.d() == 4);
    assert(f1.array[0 .. 4] == [255, 0, 0, 0]); // background fill, transparent
    assert(f1.array[4 .. 8] == [0, 255, 0, 255]); // frame 1's own green, opaque
    assert(f1.array[8 .. 12] == [255, 0, 0, 255]); // frame 1's own red, opaque
    assert(f1.array[12 .. 16] == [255, 0, 0, 0]); // background fill, transparent
}

unittest
{
    // Failure modes mirror GifImage's own: missing file and a
    // malformed signature both report through fail()/valid().
    auto missing = new AnimGifImage("/nonexistent/path/does-not-exist.gif");
    assert(!missing.valid());
    assert(missing.fail() == Image.errFormat); // see this module's top comment

    auto bad = new AnimGifImage("bad", [0, 1, 2, 3], 4);
    assert(!bad.valid());
}
