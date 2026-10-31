/*
 * Port of `FL/gl.h`'s own wrapper functions (`gl_color()`/`gl_font()`/
 * `gl_draw()`/etc -- built on the raw GL/GLX bindings in `fl.opengl`/
 * `fl.glx`) + `src/gl_draw.cxx` (FLTK 1.5.0).
 *
 * **Two text paths, as in FLTK's `gl_draw.cxx`.** By default text is
 * drawn through a cache of textures (`gl_texture_fifo`,
 * `draw_string_with_texture()`), which needs OpenGL 3 or the
 * GL_EXT/ARB_texture_rectangle extension. When neither is there, or the
 * program calls `fl.core.drawGlTextWithTextures(false)` (at any time;
 * the next `gl_font()` or `gl_draw()` follows it), text goes through the platform's bitmap fonts in
 * GL display lists instead (`draw_string_legacy_get_list()`): on X11 a
 * core X font close to the current font, loaded with `XLoadQueryFont()`
 * and turned into lists by `glXUseXFont()` (FLTK's
 * `load_xfont_for_xft2()`), so only its Latin-1 range draws; on Windows
 * the GDI font itself through `wglUseFontBitmapsW()`, loaded 1024 code
 * points at a time. FLTK's last resort, GLUT's stroke font, is not
 * ported, so on Wayland, which has no bitmap fonts for GL, text always
 * uses textures.
 *
 * **The texture cache (`Fifo`) is a faithful, if D-idiomatic, port of
 * FLTK's `gl_texture_fifo`**: a fixed-size circular buffer of
 * precomputed `(text, font, size, scale) -> GLuint` entries, evicted
 * oldest-first once full, sized via `gl_texture_pile_height()` (default
 * 100, matching FLTK). This is a real, deliberate choice over an
 * unbounded `GLuint[Key]` associative-array cache: an app redrawing
 * the same dynamic-content GL scene every frame (this port's own
 * `smoke-tests/gl_compositing.d` included) would otherwise never free
 * old textures for one-off strings, a real, unbounded GPU-memory leak
 * over a long-running session -- the bounded FIFO is FLTK's actual
 * answer to that, ported as-is rather than reinvented.
 *
 * **Text rasterization reuses `fl.image_surface.ImageSurface` and the
 * real, already-ported native Xft text path** (`alphaMaskForString()`,
 * ported from `Fl_Gl_Window_Driver::alpha_mask_for_string()`): render
 * the string via the ordinary `fl_draw()` Xft leaf into an offscreen
 * buffer, then fake an alpha channel from the rendered green channel
 * (matching FLTK's own "black background, white text" trick
 * exactly) and upload that as a `GL_ALPHA8` texture. This is why
 * Phase 3 needed no font-shaping work of its own -- it's entirely
 * built on Phase-1-and-earlier machinery (`fl.draw`'s real Xft
 * binding), just redirected through an offscreen surface and then GL.
 *
 * **Not ported**: the end-of-string raster-position advance FLTK's
 * `display_texture()` does via `gluUnProject()` (converting a screen-
 * space width back into the caller's own, possibly arbitrary, object-
 * space coordinates) -- `fl.glu` exists (see that module's own doc
 * comment) but this module doesn't use it for this narrow, documented
 * gap rather than silently getting it wrong. A caller chaining multiple
 * `gl_draw()` calls back to back without an explicit `glRasterPos*()`
 * between them sees each one start from the *same* position rather
 * than advancing -- real callers (`gl_draw(str,x,y)`, matching
 * `source/test/cube.d`'s own usage) are unaffected, since each call
 * already sets its own raster position explicitly.
 *
 * `gl_rect()`/`gl_rectf()`/`gl_color()`/`gl_draw_image()` are simple,
 * direct ports (no text-cache dependency at all) -- see each
 * function's own doc comment.
 *
 * `gl_start()`/`gl_finish()` (`src/gl_start.cxx` -- drawing GL directly
 * into an arbitrary, non-`Fl_Gl_Window` window) and `Fl::gl_visual()`
 * (`FL/Fl.H`, ported here as `glVisual()` rather than in `fl.core`, to
 * keep `fl.core` free of any GL-specific dependency) are real too, see
 * their own doc comments below. The software-simulated overlay
 * (`Fl_Gl_Overlay.cxx`) is real too, see `fl.gl_window`'s own doc
 * comment.
 */
module fl.gl;

version (linux) version = FldtkGl;
version (Windows) version = FldtkGl;

version (FldtkGl):

import fl.opengl;
import fl.enumerations : Color, Font, Fontsize, Align, black, white;
import fldraw = fl.draw;
import fl.image_surface : SurfaceDevice, ImageSurface;
import fl.window : Window;
import fl.core;
import glDriver = fl.gl_window_driver;

import fl.gl_window_driver : GLContext;

/// Ported from `gl_color(Fl_Color)`. FLTK's own `overlay_color()`
/// hardware/simulated-overlay check is skipped -- no `GlWindow` in this
/// port ever reports overlay support (`canDoOverlay()`/`can_do_overlay()`
/// is unconditionally false on X11 FLTK too, see this module's own
/// top comment on overlay's deferred status), so that branch is always
/// dead code here regardless.
void gl_color(Color i)
{
    ubyte r, g, b;
    fldraw.colorToRgb8(i, r, g, b);
    glColor3ub(r, g, b);
}

/// Outlines the given rectangle in the current `gl_color()`. Ported
/// from `gl_rect(int,int,int,int)`.
void gl_rect(int x, int y, int w, int h)
{
    if (w < 0) { w = -w; x = x - w; }
    if (h < 0) { h = -h; y = y - h; }
    glBegin(GL_LINE_LOOP);
    int r = x + w - 1, b = y + h - 1;
    glVertex2i(r, b);
    glVertex2i(r, y);
    glVertex2i(x, y);
    glVertex2i(x, b);
    glEnd();
}

/// Fills the given rectangle in the current `gl_color()`. Ported from
/// `gl_rectf(int,int,int,int)`.
void gl_rectf(int x, int y, int w, int h)
{
    glRecti(x, y, x + w, y + h);
}

/// Draws a raw 8-bit-per-channel image at the raster position `(x,y)`.
/// Ported from `gl_draw_image()` -- a plain `glDrawPixels()` call, no
/// texture cache involved (unlike text, this doesn't need one: it's
/// drawn once, not redrawn from a persistent cache keyed by content).
///
/// `d` selects `glDrawPixels()`'s format via the real, complete 1..4
/// mapping (`GL_LUMINANCE`/`GL_LUMINANCE_ALPHA`/`GL_RGB`/`GL_RGBA`),
/// matching FLTK's own `gl_draw_image()` format table -- `d==1`
/// (plain grayscale) and `d==2` (grayscale+alpha, matching
/// `fl.image.RGBImage`'s own documented `d()` convention -- see
/// `fl.png_image`'s own doc comment, and exactly what a PNG
/// color-type-4 file decodes to) both need their own format, not just
/// `GL_RGB`/`GL_RGBA`: OpenGL reading 3 or 4 bytes per pixel from a
/// buffer that only has 1 or 2 shears/misinterprets every pixel after
/// the first.
void gl_draw_image(const(ubyte)* buf, int x, int y, int w, int h, int d = 3, int ld = 0)
{
    if (!ld) ld = w * d;
    GLint rowLength;
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, ld / d);
    glRasterPos2i(x, y);
    static immutable GLenum[4] formats = [GL_LUMINANCE, GL_LUMINANCE_ALPHA, GL_RGB, GL_RGBA];
    glDrawPixels(w, h, formats[d - 1], GL_UNSIGNED_BYTE, buf);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
}

// ---- Text metrics: thin passthroughs to fl.draw's own real, always-
// native/undispatched text state (see fl.graphics_driver.GraphicsDriver's
// own doc comment for why metrics never dispatch) -- ported from
// gl_height()/gl_descent()/gl_width()*3/gl_font()/gl_measure().

/// Sets the font `gl_draw()` uses, the same font as `fl_font()`. Ported
/// from `gl_font(int, int)`. It needs a current GL context, and decides
/// how text is drawn: see this module's top comment
/// and `fl.core.drawGlTextWithTextures()`.
void gl_font(Font face, Fontsize size)
{
    chooseTextPath();
    fldraw.fl_font(face, size);
    if (!hasTextureRectangle_) glBitmapFont(face, size);
}

int gl_height() { return fldraw.height(); } /// Ported from `gl_height()`.
int gl_descent() { return fldraw.descent(); } /// Ported from `gl_descent()`.
double gl_width(const(char)[] str) { return fldraw.width(str); } /// Ported from `gl_width(const char*)`.
double gl_width(const(char)[] str, int n) { return fldraw.width(str[0 .. n]); } /// Ported from `gl_width(const char*,int)`.
double gl_width(char c) { return fldraw.width((&c)[0 .. 1]); } /// Ported from `gl_width(uchar)`.

/// Measures how wide/tall `str` will be when drawn by `gl_draw()`.
/// Ported from `gl_measure()`'s `fl_measure(str,x,y,0)`, where the `0`
/// is `draw_symbols`: gl_draw() text is measured without '@'-symbols,
/// as it is drawn.
void gl_measure(const(char)[] str, out int x, out int y)
{
    // `x` starts at 0 (D `out` params are auto-initialized):
    // fl_measure()'s "0 = natural size, no wrapping".
    fldraw.fl_measure(str, x, y, false);
}

// ---- Texture-cache text drawing (see this module's own top comment
// for the full mechanism and what's deliberately not ported) ----

private bool textPathChosen_;
private bool hasTextureRectangle_;

/// Ported from the check at the top of `gl_font()`: textures are used
/// when `drawGlTextWithTextures()` allows them and the GL driver is
/// version 3 or later or has a texture-rectangle extension. The choice
/// is made again whenever the program changes
/// `drawGlTextWithTextures()`, so text can switch paths at run time.
private void chooseTextPath()
{
    if (textPathChosen_ && drawGlTextWithTextures() == hasTextureRectangle_) return;
    textPathChosen_ = true;
    hasTextureRectangle_ = false;
    if (drawGlTextWithTextures())
    {
        import core.stdc.stdio : sscanf;
        import std.string : fromStringz;
        import std.algorithm.searching : canFind;

        int major;
        auto ver = cast(const(char)*) glGetString(GL_VERSION);
        if (ver !is null) sscanf(ver, "%d", &major);
        if (major >= 3)
            hasTextureRectangle_ = true;
        else
        {
            auto ext = cast(const(char)*) glGetString(GL_EXTENSIONS);
            if (ext !is null)
            {
                auto extStr = fromStringz(ext);
                hasTextureRectangle_ = extStr.canFind("GL_EXT_texture_rectangle")
                    || extStr.canFind("GL_ARB_texture_rectangle");
            }
        }
    }
    if (!hasTextureRectangle_ && !haveBitmapFonts())
        hasTextureRectangle_ = true; // no other way to draw text here
    drawGlTextWithTextures(hasTextureRectangle_);
}

// ---- Bitmap-font text in display lists, used when textures are not ----

/// Whether this platform can turn fonts into GL display lists.
private bool haveBitmapFonts()
{
    version (Windows) return true;
    else
    {
        import fl.platform : backend, Backend;
        return backend() == Backend.x11;
    }
}

private struct ListFont
{
    Font face;
    Fontsize size;
}

/// The display lists for one font, ported from `Fl_Font_Descriptor`'s
/// `listbase` (and, on Windows, `glok`).
private struct FontLists
{
    GLuint base;
    version (Windows) bool[64] planeLoaded; // per 1024 code points
}

private FontLists[ListFont] fontLists_;

/// How many lists each font gets -- ported from `genlistsize()`.
private int listCount()
{
    version (Windows) return 0x10000;
    else return 256;
}

/// Makes the display lists for `(face, size)` current, creating them if
/// needed. Ported from `Fl_X11_Gl_Window_Driver::gl_bitmap_font()` and
/// `Fl_WinAPI_Gl_Window_Driver::gl_bitmap_font()`.
private FontLists* glBitmapFont(Font face, Fontsize size)
{
    auto key = ListFont(face, size);
    auto lists = key in fontLists_;
    if (lists is null)
    {
        FontLists entry;
        entry.base = glGenLists(listCount());
        version (Windows) {}
        else
        {
            import fl.xlib : XFreeFont;
            import platformX11 = fl.platform_x11;

            auto font = loadCoreFont(face, size);
            if (font !is null)
            {
                int first = font.minCharOrByte2;
                int count = font.maxCharOrByte2 - first + 1;
                if (first + count > 256) count = 256 - first;
                if (count > 0) glXUseXFont(font.fid, first, count, entry.base + first);
                XFreeFont(platformX11.x11Display(), font);
            }
        }
        fontLists_[key] = entry;
        lists = key in fontLists_;
    }
    glListBase(lists.base);
    return lists;
}

version (Windows)
{
    /// Loads the 1024 code points of plane `r` into `lists`. Ported from
    /// `Fl_WinAPI_Gl_Window_Driver::get_list()`.
    private void loadPlane(FontLists* lists, Font face, Fontsize size, int r)
    {
        import core.sys.windows.windef : HDC;
        import core.sys.windows.wingdi : CreateCompatibleDC, DeleteDC, SelectObject, wglUseFontBitmapsW;
        import platformWin32 = fl.platform_win32;

        if (lists.planeLoaded[r]) return;
        lists.planeLoaded[r] = true;
        HDC dc = CreateCompatibleDC(null);
        SelectObject(dc, platformWin32.plainGraphicsDriver().fontHandle(face, size));
        uint first = r * 0x400;
        wglUseFontBitmapsW(dc, first, 0x400, lists.base + first);
        DeleteDC(dc);
    }
}
else
{
    import fl.glx : glXUseXFont;
    import fl.xlib : XFontStruct;

    /// Finds a core X font close to `(face, size)`, falling back through
    /// similar names and finally "fixed". Ported from
    /// `load_xfont_for_xft2()` (`Fl_Xlib_Graphics_Driver_font_xft.cxx`).
    private XFontStruct* loadCoreFont(Font face, Fontsize size)
    {
        import std.format : format;
        import std.string : toStringz;
        import fl.xlib : XLoadQueryFont, XFreeFont;
        import platformX11 = fl.platform_x11;

        auto dpy = platformX11.x11Display();
        XFontStruct* load(string xlfd) { return XLoadQueryFont(dpy, xlfd.toStringz); }

        string weight = "medium";
        char slant = 'r';
        string name = fldraw.getFont(face);
        if (name.length)
        {
            switch (name[0])
            {
                case 'I': slant = 'i'; name = name[1 .. $]; break;
                case 'P': slant = 'i'; weight = "bold"; name = name[1 .. $]; break;
                case 'B': weight = "bold"; name = name[1 .. $]; break;
                case ' ': name = name[1 .. $]; break;
                default: break;
            }
        }

        // Does the face exist at all, and then at this size?
        XFontStruct* font = load(format("-*-%s-%s-%c-*--*-*-*-*-*-*-*-*", name, weight, slant));
        if (font !is null)
        {
            XFreeFont(dpy, font);
            font = load(format("-*-%s-%s-%c-*--*-%d-*-*-*-*-*-*", name, weight, slant, size * 10));
        }
        if (font is null)
        {
            switch (name)
            {
                case "sans": name = "helvetica"; if (slant == 'i') slant = 'o'; break;
                case "mono", "monospace": name = "courier"; break;
                case "serif": name = "times"; break;
                case "screen": name = "lucidatypewriter"; break;
                case "dingbats": name = "zapf dingbats"; break;
                default: break;
            }
            font = load(format("-*-*%s*-%s-%c-*--*-%d-*-*-*-*-*-*", name, weight, slant, size * 10));
        }
        if (font is null)
            font = load(format("-*-helvetica-*-%c-*--*-%d-*-*-*-*-*-*", slant, size * 10));
        if (font is null && weight != "medium")
            font = load(format("-*-courier*-%s-%c-*--*-%d-*-*-*-*-*-*", weight, slant, size * 10));
        if (font is null)
            font = load(format("-*-courier*-medium-%c-*--*-%d-*-*-*-*-*-*", slant, size * 10));
        if (font is null) font = load("fixed");
        return font;
    }
}

/// Draws `str` with the current font's display lists at the current
/// raster position. Ported from `draw_string_legacy_get_list()`.
private void drawStringLegacy(const(char)[] str)
{
    import std.utf : toUTF16;

    wstring buf = toUTF16(str);
    Font face = fldraw.fl_font();
    Fontsize size = fldraw.fl_size();
    if (glStartScale_ != 1) // between gl_start() and gl_finish()
        fldraw.fl_font(face, cast(Fontsize)(size * glStartScale_));
    auto lists = glBitmapFont(fldraw.fl_font(), fldraw.fl_size());
    version (Windows)
        foreach (wchar c; buf)
            loadPlane(lists, fldraw.fl_font(), fldraw.fl_size(), (c & 0xFC00) >> 10);
    glCallLists(cast(GLsizei) buf.length, GL_UNSIGNED_SHORT, buf.ptr);
    if (glStartScale_ != 1) fldraw.fl_font(face, size);
}

/// Deletes the display lists made for drawing text without textures.
/// Ported from `gl_remove_displaylist_fonts()` (`FL/gl_draw.H`); call it
/// with the GL context current before that context goes away.
void gl_remove_displaylist_fonts()
{
    foreach (ref lists; fontLists_)
        glDeleteLists(lists.base, listCount());
    fontLists_ = null;
}

/// Drops the record of display lists that went away with the last GL
/// context.
package(fl) void forgetDisplaylistFonts()
{
    fontLists_ = null;
}

/// One cached string texture -- ported from `gl_texture_fifo::data`.
private struct FifoEntry
{
    GLuint texName;
    string text;
    Font face;
    Fontsize size;
    float scale;
}

private FifoEntry[] fifo_;
private int fifoCurrent_ = -1;
private int fifoLast_ = -1;
private bool fifoTexturesGenerated_;

private void ensureFifo()
{
    if (fifo_.length == 0) fifo_ = new FifoEntry[100]; // FLTK's own default height
}

private void freeFifoTextures()
{
    if (fifoTexturesGenerated_)
        foreach (ref e; fifo_)
            if (e.texName)
            {
                GLuint t = e.texName;
                glDeleteTextures(1, &t);
            }
}

/// The current maximum height of the texture-cache pile. Ported from
/// `gl_texture_pile_height(void)`.
int gl_texture_pile_height()
{
    ensureFifo();
    return cast(int) fifo_.length;
}

/// Changes the maximum height of the texture-cache pile, discarding
/// every currently cached texture. Ported from `gl_texture_pile_height(int)`.
void gl_texture_pile_height(int max)
{
    freeFifoTextures();
    fifo_ = new FifoEntry[max];
    fifoCurrent_ = -1;
    fifoLast_ = -1;
    fifoTexturesGenerated_ = false;
}

/// Discards every cached texture without changing the pile's size --
/// call after GL operations that may invalidate them (e.g. switching
/// FL_DOUBLE/FL_SINGLE). Ported from `gl_texture_reset()`.
void gl_texture_reset()
{
    if (fifo_.length) gl_texture_pile_height(cast(int) fifo_.length);
}

private int alreadyKnown(const(char)[] str, Font face, Fontsize size, float scale)
{
    foreach (rank; 0 .. fifoLast_ + 1)
        if (fifo_[rank].text == str && fifo_[rank].face == face
            && fifo_[rank].size == size && fifo_[rank].scale == scale)
            return rank;
    return -1;
}

/// Ported from `Fl_Gl_Window_Driver::alpha_mask_for_string()`: renders
/// `str` via the real, native Xft `fl_draw()` leaf into an offscreen
/// `ImageSurface`, then fakes an alpha channel from the rendered green
/// channel (black background = transparent, white text = opaque --
/// matching FLTK's own trick exactly, not a fldtk simplification).
///
/// `w`/`h` are the exact device-pixel size the real offscreen
/// `ImageSurface` is allocated at (`computeTexture()`'s own
/// `((ceil(logicalW*scale)+3)/4)*4` and `round(logicalH*scale)`,
/// matching FLTK's `gl_texture_fifo::compute_texture()` exactly) --
/// deliberately not FLTK-unit `logicalW`/`logicalH` relying on
/// `fl_rectf()`/`fl_draw()`'s *own* internal `scaledFloor()` rescaling
/// to land back on `w`/`h`, since `scaledFloor()` truncates
/// (`int(x*s + 0.001)`) while `computeTexture()`'s own `w`/`h`
/// round/ceil instead, so the two could disagree by a pixel or more,
/// leaving a strip of the surface's raw, uninitialized memory
/// unfilled (misread as opaque alpha, since alpha here comes from the
/// green channel -- see this function's own top comment).
///
/// This works the same way `fl.core.transientScaleDisplay()` solves
/// this identical class of bug: force `fl.core.currentScale()` to `1`
/// for the duration of this offscreen render (restored after), and work in
/// already-device-pixel units throughout -- `size` here is the real
/// device-pixel font size (`computeTexture()`'s own `size * scale`,
/// matching FLTK's own already-scaled `fs` argument to the real
/// `alpha_mask_for_string()`), and the fill/draw calls use `w`/`h`
/// directly, so there's only one rounding (the caller's `w`/`h`
/// computation) instead of two disagreeing ones -- the fill always
/// covers the *entire* real surface, by construction.
private ubyte[] alphaMaskForString(const(char)[] str, Font face, Fontsize size, int w, int h)
{
    auto surf = new ImageSurface(w, h);
    SurfaceDevice.pushCurrent(surf);

    float savedScale = currentScale();
    currentScale(1.0f);
    scope (exit) currentScale(savedScale);

    fldraw.fl_color(black);
    fldraw.fl_rectf(0, 0, w, h);
    fldraw.fl_color(white);
    fldraw.fl_font(face, size); // re-establish the font against the new surface, matching FLTK's own defensive re-set here
    int descent = fldraw.descent(); // device pixels now (currentScale() forced to 1 above), matching fl_draw()'s own expected units below
    fldraw.fl_draw(str, cast(int) str.length, 0, h - descent);
    auto image = surf.image();
    SurfaceDevice.popCurrent();

    auto alpha = new ubyte[w * h];
    if (image !is null)
        foreach (i; 0 .. w * h)
            alpha[i] = image.array[i * 3 + 1];
    return alpha;
}

/// Ported from `gl_texture_fifo::compute_texture()`. Returns the fifo
/// *rank* the string was cached at (matching `alreadyKnown()`'s own
/// return convention -- see `drawStringWithTexture()`'s caller, which
/// passes this straight into `displayTexture(rank, ...)`), not the
/// GL texture name.
///
/// Returns the rank (`fifoCurrent_`), not the texture name: every
/// caller treats the return value as a fifo *rank* (`alreadyKnown()`'s
/// own return convention, 0-based), then indexes `fifo_[rank]` with it
/// directly (`displayTexture()`'s own `fifo_[rank].texName` lookup).
/// Returning the real OpenGL texture *name* `glGenTextures()` assigned
/// that slot instead (this port's own FIFO pre-generates all names
/// upfront, sequentially starting at 1 -- see `drawStringWithTexture()`'s
/// texture-generation loop) would be off by one for as long as the
/// FIFO hasn't wrapped (`texName == rank + 1`, since names start at 1
/// while ranks start at 0): the caller would look up `fifo_[rank + 1]`
/// instead of `fifo_[rank]`, a neighboring slot whose own texture was
/// pre-generated (a valid, non-zero GL name exists) but never actually
/// uploaded via `glTexImage2D` -- querying its size via
/// `glGetTexLevelParameteriv()` reads back `0x0`, producing a
/// zero-sized, invisible quad on that string's first draw. The name
/// itself is only ever needed internally, via `fifo_[rank].texName`.
private int computeTexture(const(char)[] str, Font face, Fontsize size, float scale)
{
    fifoCurrent_ = (fifoCurrent_ + 1) % cast(int) fifo_.length;
    if (fifoCurrent_ > fifoLast_) fifoLast_ = fifoCurrent_;

    // Render at the plain, unscaled `size` -- NOT `size * scale`.
    // fl.draw's own `fl_font()` (called here, and again inside
    // alphaMaskForString() below) already opens the font at `size *
    // fl.core.currentScale()` device pixels internally (see that function's
    // own doc comment) -- this port's `fl_font()` isn't a bare,
    // unscaled primitive the way FLTK's own font-selection call at
    // the equivalent spot in `gl_texture_fifo::compute_texture()` is,
    // so pre-multiplying by `scale` here on top of that would scale the
    // same value twice.
    //
    // `width(str)`/`height()` themselves return *logical* (FLTK-unit)
    // measurements -- divided back down from the real device-pixel
    // font internally, matching every other consumer of these two
    // functions in this port (see their own doc comments) -- so the
    // texture/surface these measurements size still needs its own
    // explicit `* scale` to reach the real device-pixel size large
    // enough to hold the actual (correctly device-pixel-sized) glyph
    // rendering `alphaMaskForString()` produces.
    fldraw.fl_font(face, size);
    int logicalW = cast(int)(fldraw.width(str) + 0.999);
    int logicalH = fldraw.height();
    int w = ((cast(int)(logicalW * scale + 0.999) + 3) / 4) * 4; // multiple of 4, matching FLTK
    int h = cast(int)(logicalH * scale + 0.5f);

    // alphaMaskForString() now works entirely in device pixels (see its
    // own doc comment for why) -- the font it opens needs to be the
    // real device-pixel size to match, not the logical `size` (which
    // fl_font() would otherwise re-scale by fl.core.currentScale() itself,
    // wrongly landing back on `size` again since alphaMaskForString()
    // forces that scale to 1 for its own duration). Matches FLTK's
    // own already-scaled `fs = int(fs * gl_scale)` argument to the real
    // `alpha_mask_for_string()` exactly.
    Fontsize devSize = cast(Fontsize)(size * scale);
    if (devSize < 1) devSize = 1;
    auto alpha = alphaMaskForString(str, face, devSize, w, h);

    GLint rowLength, alignment;
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);

    glPushAttrib(GL_TEXTURE_BIT);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, fifo_[fifoCurrent_].texName);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glPixelStorei(GL_UNPACK_ROW_LENGTH, w);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, GL_ALPHA8, w, h, 0, GL_ALPHA, GL_UNSIGNED_BYTE, alpha.ptr);
    glPopAttrib();
    glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
    glPixelStorei(GL_UNPACK_ALIGNMENT, alignment);

    fifo_[fifoCurrent_].text = str.idup;
    fifo_[fifoCurrent_].face = face;
    fifo_[fifoCurrent_].size = size;
    fifo_[fifoCurrent_].scale = scale;
    return fifoCurrent_;
}

/// Ported from `gl_texture_fifo::display_texture()` -- draws a cached
/// texture as a blended quad at the current raster position.
private void displayTexture(int rank, float scale, int winW, int winH, int angle = 0)
{
    glPushAttrib(GL_TRANSFORM_BIT | GL_ENABLE_BIT | GL_TEXTURE_BIT | GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();

    float winwS = scale * winW;
    float winhS = scale * winH;
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_LIGHTING);

    GLfloat[4] pos;
    glGetFloatv(GL_CURRENT_RASTER_POSITION, pos.ptr);

    float R = 2;
    glScalef(R / winwS, R / winhS, 1.0f);
    glTranslatef(-winwS / R, -winhS / R, 0.0f);
    glEnable(GL_TEXTURE_RECTANGLE_ARB);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, fifo_[rank].texName);
    GLint width, height;
    glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE_ARB, 0, GL_TEXTURE_WIDTH, &width);
    glGetTexLevelParameteriv(GL_TEXTURE_RECTANGLE_ARB, 0, GL_TEXTURE_HEIGHT, &height);

    // The quad's corners relative to the start of the baseline, turned
    // `angle` degrees counter-clockwise about it (y points up here).
    import std.math : cos, sin, PI;

    float top = height - scale * fldraw.descent();
    float bottom = top - height;
    float c = cos(angle * PI / 180), sn = sin(angle * PI / 180);
    void corner(float tx, float ty, float dx, float dy)
    {
        glTexCoord2f(tx, ty);
        glVertex2f(pos[0] + dx * c - dy * sn, pos[1] + dx * sn + dy * c);
    }

    glBegin(GL_QUADS);
    corner(0, 0, 0, top);
    corner(0, height, 0, bottom);
    corner(width, height, width, bottom);
    corner(width, 0, width, top);
    glEnd();

    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
    glMatrixMode(GL_PROJECTION);
    glPopMatrix();
    glPopAttrib();

    // No raster-position advance here -- see this module's own top
    // comment (needs gluUnProject(), not ported).
}

private void drawStringWithTexture(const(char)[] str, int angle = 0)
{
    GLint valid;
    glGetIntegerv(GL_CURRENT_RASTER_POSITION_VALID, &valid);
    if (!valid) return;

    auto win = Window.current();
    if (win is null) return;

    // The window's GL pixels per FLTK unit (FLTK's `gl_scale`, set from
    // `pixels_per_unit()`): `displayTexture()` below uses `scale` to
    // convert the window's own *logical* `w()`/`h()` (passed in as
    // `winW`/`winH`) into the real device-pixel window size it needs to
    // correctly place the cached text texture at the current raster
    // position, and the texture is rendered at that scale. It is the
    // screen scale on X11 and Windows, and on Wayland includes the
    // screen's buffer scale too -- with the screen scale alone there,
    // the text lands outside the window on a HiDPI screen.
    float scale = glDriver.pixelsPerUnit(win);

    ensureFifo();
    if (!fifoTexturesGenerated_)
    {
        foreach (ref e; fifo_)
        {
            GLuint t;
            glGenTextures(1, &t);
            e.texName = t;
        }
        fifoTexturesGenerated_ = true;
    }

    auto face = fldraw.fl_font();
    auto size = fldraw.fl_size();
    int idx = alreadyKnown(str, face, size, scale);
    if (idx == -1) idx = computeTexture(str, face, size, scale);
    displayTexture(idx, scale, win.w(), win.h(), angle);
}

/// Draws n characters of str in the current font at the current
/// raster position. Ported from `gl_draw(const char*, int)`.
void gl_draw(const(char)[] str, int n)
{
    if (n <= 0) return;
    chooseTextPath();
    if (hasTextureRectangle_) drawStringWithTexture(str[0 .. n]);
    else drawStringLegacy(str[0 .. n]);
}

/// Draws `str` at the current raster position, turned `angle` degrees
/// counter-clockwise about the start of its baseline -- the GL graphics
/// driver's rotated text. Bitmap-font text cannot turn, so without
/// textures the string is drawn level.
package(fl) void glDrawRotated(int angle, const(char)[] str)
{
    if (str.length == 0) return;
    chooseTextPath();
    if (hasTextureRectangle_) drawStringWithTexture(str, angle);
    else drawStringLegacy(str);
}

/// Ported from `gl_draw(const char*, int, int, int)`.
void gl_draw(const(char)[] str, int n, int x, int y)
{
    glRasterPos2i(x, y);
    gl_draw(str, n);
}

/// Ported from `gl_draw(const char*, int, float, float)`.
void gl_draw(const(char)[] str, int n, float x, float y)
{
    glRasterPos2f(x, y);
    gl_draw(str, n);
}

/// Ported from `gl_draw(const char*)`.
void gl_draw(const(char)[] str)
{
    gl_draw(str, cast(int) str.length);
}

/// Ported from `gl_draw(const char*, int, int)`.
void gl_draw(const(char)[] str, int x, int y)
{
    gl_draw(str, cast(int) str.length, x, y);
}

/// Ported from `gl_draw(const char*, float, float)`.
void gl_draw(const(char)[] str, float x, float y)
{
    gl_draw(str, cast(int) str.length, x, y);
}

private void glDrawInvert(const(char)[] str, int n, int x, int y)
{
    glRasterPos2i(x, -y);
    gl_draw(str, n);
}

/// Draws str formatted into a box, with newlines/tabs expanded and
/// aligned within it -- exactly the same layout `fl_draw()` produces.
/// Ported from `gl_draw(const char*,int,int,int,int,Fl_Align)`, reusing
/// `fl.draw`'s own callback-based `fl_draw()` overload (the same one
/// `Fl_Shadow_Label`/etc use, see that function's own doc comment) with
/// `glDrawInvert()` as the per-line draw callback, matching FLTK's
/// `gl_draw_invert()` exactly.
void gl_draw(const(char)[] str, int x, int y, int w, int h, Align alignment)
{
    fldraw.fl_draw(str.idup, x, -y - h, w, h, alignment,
        (const(char)[] s, int n, int X, int Y) { glDrawInvert(s, n, X, Y); }, null, 0,
        false); // FLTK's trailing `NULL, 0` is img and draw_symbols = 0, not spacing
}

// ---------------------------------------------------------------------
// gl_start()/gl_finish(): drawing GL directly into an arbitrary,
// non-GlWindow window's own draw() -- ported from `src/gl_start.cxx`.
// ---------------------------------------------------------------------

private GLContext glStartContext_; // ported from `Fl_Gl_Window_Driver::gl_start_context`
private int glStartPixelW_, glStartPixelH_; // ported from `gl_start.cxx`'s own file-local `pw`/`ph`
private float glStartScale_ = 1;

/// Ported from `Fl::gl_visual(int, int*)` (`FL/Fl.H`) -- deliberately
/// homed here rather than `fl.core` to keep that module free of any
/// GL-specific dependency (see this module's own top comment). Selects
/// the GL-capable visual/pixel-format every window fldtk creates
/// afterward uses -- **must be called before `show()`ing any window**;
/// Mesa crashes if a GL context is made current against a visual GLX
/// didn't choose itself (`FL/gl.h`'s own doc comment). Returns `false`
/// if no matching visual/pixel-format exists.
bool glVisual(int mode, const(int)* alist = null)
{
    // On Wayland, gl_start() draws into a surface over the window, which
    // must be transparent where nothing is drawn.
    if (glDriver.alwaysDoubleBuffered())
    {
        import fl.enumerations : modeAlpha;
        mode |= modeAlpha;
    }
    auto c = glDriver.find(mode, alist);
    if (c is null) return false;
    glDriver.glVisual(c);
    return true;
}

/**
 * Ported from `gl_start()` (`src/gl_start.cxx`): lets an application draw
 * plain OpenGL directly into the window currently being drawn
 * (`Window.current()`) without that window being a `GlWindow` at all --
 * e.g. from a plain `Box` subclass's `draw()` override. Bracket such a
 * `draw()` override entirely between `gl_start()` and `gl_finish()`.
 *
 * Two real FLTK limitations, ported faithfully, not narrowed:
 * `glVisual()` must already have selected a GL-capable visual before the
 * target window was first shown (this lazily picks the plain default,
 * mode `0`, the first time `gl_start()` ever runs if the caller never
 * called `glVisual()` explicitly first -- matching FLTK's own
 * `if (!gl_choice) Fl::gl_visual(0);`); and **this does not work with a
 * double-buffered window** -- it draws straight into the front buffer,
 * which a double-buffered window's own repaint can immediately overwrite
 * or leave undrawn depending on the platform/driver, matching
 * `src/gl_start.cxx`'s own top comment exactly. On Wayland neither
 * applies: GL draws into a transparent surface over the window, shown
 * with the window's own next frame (see `fl.wayland_gl_window_driver`'s
 * module comment).
 *
 * No `fl_clip_state_number`-style change-counting here (this port's clip
 * model is a plain rectangle stack, not FLTK's general `Fl_Region`) --
 * the scissor rect is just recomputed from `fl.draw.clipBox()` on every
 * call instead, the same simplification `notClipped()`/`clipBox()`
 * already make throughout this port (see `fl.draw`'s own "Clipping"
 * section).
 */
void gl_start()
{
    auto win = Window.current();
    glStartScale_ = currentScale();

    if (glStartContext_ is null)
    {
        if (glDriver.glChoice_ is null) glVisual(0);
        glStartContext_ = glDriver.createGlContext(win, glDriver.glChoice_);
    }
    glDriver.setGlContext(win, glStartContext_);
    // the pixels per FLTK unit of what GL draws into
    float s = glDriver.glStart(win, glStartScale_);

    int w = cast(int)(win.w() * s);
    int h = cast(int)(win.h() * s);
    if (glStartPixelW_ != w || glStartPixelH_ != h)
    {
        glStartPixelW_ = w;
        glStartPixelH_ = h;
        glLoadIdentity();
        glViewport(0, 0, w, h);
        glOrtho(0, win.w(), 0, win.h(), -1, 1);
        glDrawBuffer(glDriver.glStartBuffer());
    }

    int x, y, cw, ch;
    if (fldraw.clipBox(0, 0, win.w(), win.h(), x, y, cw, ch))
    {
        glScissor(cast(int)(x * s), cast(int)((win.h() - (y + ch)) * s),
            cast(int)(cw * s), cast(int)(ch * s));
        glEnable(GL_SCISSOR_TEST);
    }
    else
    {
        glDisable(GL_SCISSOR_TEST);
    }

    currentScale(1);
}

/// Ported from `gl_finish()` (`src/gl_start.cxx`) -- releases what
/// `gl_start()` set up.
void gl_finish()
{
    glFlush();
    glDriver.waitGL();
    currentScale(glStartScale_);
    glStartScale_ = 1;
}
