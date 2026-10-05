/*
 * Ported from FL/Fl_Color_Chooser.H + src/Fl_Color_Chooser.cxx (FLTK
 * 1.5.0). A standard RGB color chooser: a "hue
 * box" (click/drag to pick hue+saturation, or a circular wheel),
 * a vertical brightness slider, and three numeric fields that can show
 * rgb/byte/hex/hsv values via a dropdown. Plus `colorChooser()`,
 * a ready-made modal popup dialog built on top of it.
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - `HueBox`/`ValueBox.draw()` call the callback-based
 *    `fl.draw.drawImage()` overload -- a direct port of FLTK's own
 *    `generate_image()`/`generate_vimage()` feeding `fl_draw_image()`
 *    -- reducing every redraw to one `XPutImage()` call each, matching
 *    FLTK's own single-blit repaint exactly (rather than a
 *    per-pixel `fl_color()`+`point()`/`fl_xyline()` loop, which would
 *    cost roughly 13,000 individual X protocol round-trips for a
 *    115x115 hue box on every redraw). Also matches FLTK's own
 *    `damage() == FL_DAMAGE_EXPOSE` optimization, clipping a plain
 *    re-expose repaint to just the crosshair-sized region instead of
 *    regenerating the whole gradient.
 *  - **`Flcc_HueBox::handle()`'s function-local `static double ih,
 *    is;`** (and `Flcc_ValueBox::handle()`'s `static double iv;`) are
 *    ported as private *module*-level globals (`hueboxIh_`/
 *    `hueboxIs_`/`valueboxIv_`), not per-instance fields -- matching
 *    the established "genuinely shared C++ function-local static"
 *    precedent already documented for `fl.slider`'s `offcenter` and
 *    `fl.roller`'s `ipos` (`CONVENTIONS.md`'s porting-conventions section):
 *    faithfully reproduce the sharing rather than silently making it
 *    per-instance, even though in practice a single `ColorChooser`
 *    (and therefore a single live `HueBox`/`ValueBox` pair) is the
 *    overwhelmingly common case.
 *  - `hsv2rgb()` takes its outputs as `out double` parameters (every
 *    branch fully assigns them, so no behavior change from FLTK's
 *    `double&`). `rgb2hsv()` uses `ref double` instead -- see that
 *    method's own doc comment for why `out`'s forced NaN-reset would
 *    diverge from FLTK's real behavior when R==G==B.
 */
module fl.color_chooser;

import std.math : fmod, sqrt, atan2, cos, sin, PI;
import std.format : format;

import fl.enumerations;
import fl.widget : Widget;
import fl.group : FlGroup;
import fl.box : Box;
import fl.button : Button;
import fl.return_button : ReturnButton;
import fl.choice : Choice;
import fl.value_input : ValueInput;
import fl.menu_item : MenuItem;
import fl.window : Window;
import fl.ask : ok, fl_cancel;
import fl.draw;
import fl.core;

private enum modeRgb = 0;
private enum modeByte = 1;
private enum modeHex = 2;
private enum modeHsv = 3;

private MenuItem[] modeMenuItems()
{
    return [
        MenuItem("rgb"),
        MenuItem("byte"),
        MenuItem("hex"),
        MenuItem("hsv"),
        MenuItem(null),
    ];
}

/// Converts a (fractional 0..1) x,y position within the hue box into
/// hue (0..6) / saturation (0..1) -- the "CIRCLE" variant FLTK
/// builds by default (a circular wheel, not a rectilinear gradient).
private void tohs(double x, double y, out double h, out double s)
{
    x = 2 * x - 1;
    y = 1 - 2 * y;
    s = sqrt(x * x + y * y);
    if (s > 1.0) s = 1.0;
    h = (3.0 / PI) * atan2(y, x);
    if (h < 0) h += 6.0;
}

private double hueboxIh_, hueboxIs_; // see this module's own top comment
private double valueboxIv_;

/// For internal use only.
private final class HueBox : Widget
{
    private int px, py;

    this(int X, int Y, int W, int H) { super(X, Y, W, H); }

    private ColorChooser owner() { return cast(ColorChooser) parent(); }

    protected override void draw()
    {
        if ((damage() & damageAll) != 0) drawBox();
        int x1 = x() + fl.core.boxDx(box());
        int y1 = y() + fl.core.boxDy(box());
        int w1 = w() - fl.core.boxDw(box());
        int h1 = h() - fl.core.boxDh(box());
        if (w1 > 0 && h1 > 0)
        {
            double V = owner().value();
            // Ported from Fl_Xlib_Graphics_Driver's own `damage() ==
            // FL_DAMAGE_EXPOSE` optimization: a plain Expose repaint
            // (no other damage bits set -- e.g. another window briefly
            // covered this one) only needs to redraw the small 6x6
            // crosshair region, not regenerate the whole gradient.
            bool exposeOnly = damage() == damageExpose;
            if (exposeOnly) pushClip(x1 + px, y1 + py, 6, 6);
            drawImage((int xx, int yy, int ww, ubyte[] buf) {
                double Yf = cast(double) yy / h1;
                size_t idx = 0;
                foreach (col; xx .. xx + ww)
                {
                    double Xf = cast(double) col / w1;
                    double H, S;
                    tohs(Xf, Yf, H, S);
                    double r, g, b;
                    ColorChooser.hsv2rgb(H, S, V, r, g, b);
                    buf[idx++] = cast(ubyte)(255 * r + .5);
                    buf[idx++] = cast(ubyte)(255 * g + .5);
                    buf[idx++] = cast(ubyte)(255 * b + .5);
                }
            }, x1, y1, w1, h1);
            if (exposeOnly) popClip();
        }
        auto c = owner();
        int X = cast(int)(.5 * (cos(c.hue() * (PI / 3.0)) * c.saturation() + 1) * (w1 - 6));
        int Y = cast(int)(.5 * (1 - sin(c.hue() * (PI / 3.0)) * c.saturation()) * (h1 - 6));
        if (X < 0) X = 0; else if (X > w1 - 6) X = w1 - 6;
        if (Y < 0) Y = 0; else if (Y > h1 - 6) Y = h1 - 6;
        if (w1 > 0 && h1 > 0)
        {
            pushClip(x1, y1, w1, h1);
            drawBox(Boxtype.upBox, x1 + X, y1 + Y, 6, 6, fl.core.focus() is this ? foregroundColor : gray0 + 12);
            popClip();
        }
        px = X;
        py = Y;
    }

    private int handleKey(int key)
    {
        int w1 = w() - fl.core.boxDw(box()) - 6;
        int h1 = h() - fl.core.boxDh(box()) - 6;
        auto c = owner();

        int X = cast(int)(.5 * (cos(c.hue() * (PI / 3.0)) * c.saturation() + 1) * w1);
        int Y = cast(int)(.5 * (1 - sin(c.hue() * (PI / 3.0)) * c.saturation()) * h1);

        switch (key)
        {
        case up: Y -= 3; break;
        case down: Y += 3; break;
        case left: X -= 3; break;
        case right: X += 3; break;
        default: return 0;
        }

        double Xf = cast(double) X / w1;
        double Yf = cast(double) Y / h1;
        double H, S;
        tohs(Xf, Yf, H, S);
        if (c.hsv(H, S, c.value())) c.doCallback(CallbackReason.changed);
        return 1;
    }

    override int handle(Event e)
    {
        auto c = owner();
        switch (e)
        {
        case Event.push:
            if (fl.core.visibleFocus())
            {
                fl.core.focus(this);
                redraw();
            }
            hueboxIh_ = c.hue();
            hueboxIs_ = c.saturation();
            goto case Event.drag;
        case Event.drag:
        {
            double Xf = (fl.core.eventX() - x() - fl.core.boxDx(box())) / cast(double)(w() - fl.core.boxDw(box()));
            double Yf = (fl.core.eventY() - y() - fl.core.boxDy(box())) / cast(double)(h() - fl.core.boxDh(box()));
            double H, S;
            tohs(Xf, Yf, H, S);
            import std.math : fabs;

            if (fabs(H - hueboxIh_) < 3 * 6.0 / w()) H = hueboxIh_;
            if (fabs(S - hueboxIs_) < 3 * 1.0 / h()) S = hueboxIs_;
            if ((fl.core.eventState() & stateCtrl) != 0) H = hueboxIh_;
            if (c.hsv(H, S, c.value())) c.doCallback(CallbackReason.dragged);
            return 1;
        }
        case Event.focus, Event.unfocus:
            if (fl.core.visibleFocus())
            {
                redraw();
                return 1;
            }
            return 1;
        case Event.keyDown:
            return handleKey(fl.core.eventKey());
        default:
            return 0;
        }
    }
}

/// For internal use only.
private final class ValueBox : Widget
{
    private int py;

    this(int X, int Y, int W, int H) { super(X, Y, W, H); }

    private ColorChooser owner() { return cast(ColorChooser) parent(); }

    protected override void draw()
    {
        if ((damage() & damageAll) != 0) drawBox();
        auto c = owner();
        double tr, tg, tb;
        ColorChooser.hsv2rgb(c.hue(), c.saturation(), 1.0, tr, tg, tb);
        int x1 = x() + fl.core.boxDx(box());
        int y1 = y() + fl.core.boxDy(box());
        int w1 = w() - fl.core.boxDw(box());
        int h1 = h() - fl.core.boxDh(box());
        if (w1 > 0 && h1 > 0)
        {
            // Same FL_DAMAGE_EXPOSE-only optimization as HueBox.draw()
            // above -- ValueBox's crosshair is a horizontal strip
            // rather than a 6x6 box, since its gradient only varies
            // with y.
            bool exposeOnly = damage() == damageExpose;
            if (exposeOnly) pushClip(x1, y1 + py, w1, 6);
            drawImage((int xx, int yy, int ww, ubyte[] buf) {
                double Yf = 255 * (1.0 - cast(double) yy / h1);
                ubyte r = cast(ubyte)(tr * Yf + .5);
                ubyte g = cast(ubyte)(tg * Yf + .5);
                ubyte b = cast(ubyte)(tb * Yf + .5);
                size_t idx = 0;
                foreach (col; 0 .. ww)
                {
                    buf[idx++] = r;
                    buf[idx++] = g;
                    buf[idx++] = b;
                }
            }, x1, y1, w1, h1);
            if (exposeOnly) popClip();
        }
        int Y = cast(int)((1 - c.value()) * (h1 - 6));
        if (Y < 0) Y = 0; else if (Y > h1 - 6) Y = h1 - 6;
        drawBox(Boxtype.upBox, x1, y1 + Y, w1, 6, fl.core.focus() is this ? foregroundColor : gray0 + 12);
        py = Y;
    }

    private int handleKey(int key)
    {
        int h1 = h() - fl.core.boxDh(box()) - 6;
        auto c = owner();

        int Y = cast(int)((1 - c.value()) * h1);
        if (Y < 0) Y = 0; else if (Y > h1) Y = h1;

        switch (key)
        {
        case up: Y -= 3; break;
        case down: Y += 3; break;
        default: return 0;
        }

        double Yf = 1 - cast(double) Y / h1;
        if (c.hsv(c.hue(), c.saturation(), Yf)) c.doCallback(CallbackReason.changed);
        return 1;
    }

    override int handle(Event e)
    {
        auto c = owner();
        switch (e)
        {
        case Event.push:
            if (fl.core.visibleFocus())
            {
                fl.core.focus(this);
                redraw();
            }
            valueboxIv_ = c.value();
            goto case Event.drag;
        case Event.drag:
        {
            double Yf = 1 - (fl.core.eventY() - y() - fl.core.boxDy(box())) / cast(double)(h() - fl.core.boxDh(box()));
            import std.math : fabs;

            if (fabs(Yf - valueboxIv_) < 3 * 1.0 / h()) Yf = valueboxIv_;
            if (c.hsv(c.hue(), c.saturation(), Yf)) c.doCallback(CallbackReason.dragged);
            return 1;
        }
        case Event.focus, Event.unfocus:
            if (fl.core.visibleFocus())
            {
                redraw();
                return 1;
            }
            return 1;
        case Event.keyDown:
            return handleKey(fl.core.eventKey());
        default:
            return 0;
        }
    }
}

/// For internal use only. Shows a hex byte ("0xXX") when the owning
/// ColorChooser is in hex mode, otherwise the ordinary numeric format.
private final class ChooserValueInput : ValueInput
{
    private ColorChooser owner_;

    this(int X, int Y, int W, int H, ColorChooser owner)
    {
        super(X, Y, W, H);
        owner_ = owner;
    }

    override string format()
    {
        // owner_ isn't assigned until after super()'s constructor body
        // finishes, but that body's own valueDamage() call already
        // dispatches virtually to this override (D resolves the vtable
        // from the start of construction, unlike C++ -- see CONVENTIONS.md's
        // "D also does not build up the vtable progressively during
        // construction" note, first hit by fl.table.Table). Guard against
        // that not-yet-constructed window.
        if (owner_ !is null && owner_.mode() == modeHex) return "0x%02X".format(cast(int) value());
        return super.format();
    }
}

/**
 * A standard RGB color chooser widget: a hue/saturation wheel, a
 * brightness slider, and rgb/byte/hex/hsv numeric fields. Place any
 * number of these into a panel of your own design, or use the
 * ready-made `fl_color_chooser()` popup below. Ported from
 * `Fl_Color_Chooser`.
 */
class ColorChooser : FlGroup
{
    private HueBox huebox_;
    private ValueBox valuebox_;
    private Choice choice_;
    private ChooserValueInput rvalue_;
    private ChooserValueInput gvalue_;
    private ChooserValueInput bvalue_;
    private Box resizeBox_;
    private double hue_, saturation_, value_;
    private double r_, g_, b_;

    /// Recommended dimensions are 200x95. The color is initialized to
    /// black.
    this(int X, int Y, int W, int H, string L = null)
    {
        super(0, 0, 195, 115, L);
        huebox_ = new HueBox(0, 0, 115, 115);
        valuebox_ = new ValueBox(115, 0, 20, 115);
        choice_ = new Choice(140, 0, 55, 25);
        rvalue_ = new ChooserValueInput(140, 30, 55, 25, this);
        gvalue_ = new ChooserValueInput(140, 60, 55, 25, this);
        bvalue_ = new ChooserValueInput(140, 90, 55, 25, this);
        resizeBox_ = new Box(0, 0, 115, 115);
        end();
        resizable(resizeBox_);
        resize(X, Y, W, H);
        r_ = g_ = b_ = 0;
        hue_ = 0.0;
        saturation_ = 0.0;
        value_ = 0.0;
        huebox_.box(Boxtype.downFrame);
        valuebox_.box(Boxtype.downFrame);
        choice_.menu(modeMenuItems());
        setValuators();
        rvalue_.callback((w) { rgbCb(); });
        gvalue_.callback((w) { rgbCb(); });
        bvalue_.callback((w) { rgbCb(); });
        choice_.callback((w) { modeCb(); });
        choice_.box(Boxtype.thinUpBox);
        choice_.textfont(helveticaBoldItalic);
    }

    /// Handles the standard "copy the current color as hex text
    /// ('RRGGBB')" shortcuts (Ctrl-C, Ctrl-X, Ctrl-Insert), letting the
    /// user paste the picked color into another application (or
    /// another text input in this one). All other events go to FlGroup.
    override int handle(Event e)
    {
        auto mods = fl.core.eventState() & (stateMeta | stateCtrl | stateAlt);
        auto shift = fl.core.eventState() & stateShift;

        if ((e == Event.keyDown || e == Event.shortcut) && shift == 0)
        {
            switch (fl.core.eventKey())
            {
            case fl.enumerations.insert:
                if (mods == stateCtrl) return copyRgb();
                break;
            case cast(int) 'c':
            case cast(int) 'x':
                if (mods == stateCommand) return copyRgb();
                break;
            default:
                break;
            }
        }
        return super.handle(e);
    }

    private int copyRgb()
    {
        string buf = "%02X%02X%02X".format(cast(int)(r_ * 255 + .5), cast(int)(g_ * 255 + .5), cast(int)(b_ * 255 + .5));
        fl.core.copy(buf, 1);
        return 1;
    }

    /// Which variant is currently active: rgb(0), byte(1), hex(2), or hsv(3).
    int mode() const { return choice_.value(); }
    /// ditto
    void mode(int newMode)
    {
        choice_.value(newMode);
        choice_.doCallback(CallbackReason.reselected);
    }

    /// The current hue. 0 <= hue < 6 (zero is red, one is yellow, two
    /// is green, etc -- convenient for the internal math, unlike the
    /// 0..1 or 0..360 scales some other systems use).
    double hue() const { return hue_; }
    /// The current saturation, 0 <= saturation <= 1.
    double saturation() const { return saturation_; }
    /// The current value/brightness, 0 <= value <= 1.
    double value() const { return value_; }
    /// The current red value, 0 <= r <= 1.
    double r() const { return r_; }
    /// The current green value, 0 <= g <= 1.
    double g() const { return g_; }
    /// The current blue value, 0 <= b <= 1.
    double b() const { return b_; }

    /// Sets the current hsv values. Clamped (or, for hue, modulus 6)
    /// to legal values. Does not do the callback. Returns 1 if a new
    /// value was set, 0 if unchanged.
    int hsv(double H, double S, double V)
    {
        H = fmod(H, 6.0);
        if (H < 0.0) H += 6.0;
        if (S < 0.0) S = 0.0; else if (S > 1.0) S = 1.0;
        if (V < 0.0) V = 0.0; else if (V > 1.0) V = 1.0;
        if (H == hue_ && S == saturation_ && V == value_) return 0;
        double ph = hue_, ps = saturation_, pv = value_;
        hue_ = H;
        saturation_ = S;
        value_ = V;
        if (value_ != pv)
        {
            huebox_.damage(damageScroll);
            valuebox_.damage(damageExpose);
        }
        if (hue_ != ph || saturation_ != ps)
        {
            huebox_.damage(damageExpose);
            valuebox_.damage(damageScroll);
        }
        hsv2rgb(H, S, V, r_, g_, b_);
        setValuators();
        setChanged();
        return 1;
    }

    /// Sets the current rgb values. Does not do the callback, does not
    /// clamp (out-of-range values produce psychedelic effects in the
    /// hue selector). Returns 1 if a new value was set, 0 if unchanged.
    int rgb(double R, double G, double B)
    {
        if (R == r_ && G == g_ && B == b_) return 0;
        r_ = R;
        g_ = G;
        b_ = B;
        double ph = hue_, ps = saturation_, pv = value_;
        rgb2hsv(R, G, B, hue_, saturation_, value_);
        setValuators();
        setChanged();
        if (value_ != pv)
        {
            huebox_.damage(damageScroll);
            valuebox_.damage(damageExpose);
        }
        if (hue_ != ph || saturation_ != ps)
        {
            huebox_.damage(damageExpose);
            valuebox_.damage(damageScroll);
        }
        return 1;
    }

    /// Converts HSV to RGB colorspace.
    static void hsv2rgb(double H, double S, double V, out double R, out double G, out double B)
    {
        if (S < 5.0e-6)
        {
            R = G = B = V;
        }
        else
        {
            int i = cast(int) H;
            double f = H - i;
            double p1 = V * (1.0 - S);
            double p2 = V * (1.0 - S * f);
            double p3 = V * (1.0 - S * (1.0 - f));
            switch (i)
            {
            case 0: R = V; G = p3; B = p1; break;
            case 1: R = p2; G = V; B = p1; break;
            case 2: R = p1; G = V; B = p3; break;
            case 3: R = p1; G = p2; B = V; break;
            case 4: R = p3; G = p1; B = V; break;
            case 5: R = V; G = p1; B = p2; break;
            default: break;
            }
        }
    }

    /// Converts RGB to HSV colorspace. H/S are `ref`, not `out` --
    /// matching FLTK's plain `double&` parameters exactly: when
    /// R==G==B (including black), hue and saturation are ambiguous/
    /// undefined and FLTK's C++ simply never writes them, leaving
    /// the caller's existing values untouched (typically the color
    /// chooser's own already-meaningful previous hue). D's `out`
    /// forces a reset to `double.init` (NaN) on every call regardless,
    /// which would silently poison a subsequent hsv2rgb() round-trip
    /// (the S<5e-6 shortcut branch is the only thing that saves such a
    /// call, and only because it ignores H entirely) -- `ref` is the
    /// faithful equivalent. Callers must pre-initialize H/S/V, exactly
    /// as every real call site here already does (ColorChooser's own
    /// hue_/saturation_/value_ fields, initialized to 0 in the
    /// constructor).
    static void rgb2hsv(double R, double G, double B, ref double H, ref double S, ref double V)
    {
        double maxv = R > G ? R : G;
        if (B > maxv) maxv = B;
        V = maxv;
        if (maxv > 0)
        {
            double minv = R < G ? R : G;
            if (B < minv) minv = B;
            S = 1.0 - minv / maxv;
            if (maxv > minv)
            {
                if (maxv == R) { H = (G - B) / (maxv - minv); if (H < 0) H += 6.0; }
                else if (maxv == G) H = 2.0 + (B - R) / (maxv - minv);
                else H = 4.0 + (R - G) / (maxv - minv);
            }
        }
    }

    private void setValuators()
    {
        final switch (mode())
        {
        case modeRgb:
            rvalue_.range(0, 1); rvalue_.step(1, 1000); rvalue_.value(r_);
            gvalue_.range(0, 1); gvalue_.step(1, 1000); gvalue_.value(g_);
            bvalue_.range(0, 1); bvalue_.step(1, 1000); bvalue_.value(b_);
            break;
        case modeByte, modeHex:
            rvalue_.range(0, 255); rvalue_.step(1); rvalue_.value(cast(int)(255 * r_ + .5));
            gvalue_.range(0, 255); gvalue_.step(1); gvalue_.value(cast(int)(255 * g_ + .5));
            bvalue_.range(0, 255); bvalue_.step(1); bvalue_.value(cast(int)(255 * b_ + .5));
            break;
        case modeHsv:
            rvalue_.range(0, 6); rvalue_.step(1, 1000); rvalue_.value(hue_);
            gvalue_.range(0, 1); gvalue_.step(1, 1000); gvalue_.value(saturation_);
            bvalue_.range(0, 1); bvalue_.step(1, 1000); bvalue_.value(value_);
            break;
        }
    }

    private void rgbCb()
    {
        // Clamp input values to valid ranges (FLTK issue #749).
        double R = rvalue_.clamp(rvalue_.value());
        double G = gvalue_.clamp(gvalue_.value());
        double B = bvalue_.clamp(bvalue_.value());
        rvalue_.value(R);
        gvalue_.value(G);
        bvalue_.value(B);
        if (mode() == modeHsv)
        {
            if (hsv(R, G, B)) doCallback(CallbackReason.changed);
            return;
        }
        if (mode() != modeRgb)
        {
            R /= 255;
            G /= 255;
            B /= 255;
        }
        if (rgb(R, G, B)) doCallback(CallbackReason.changed);
    }

    private void modeCb()
    {
        // Force a redraw even if the value is the same.
        rvalue_.value(-1);
        gvalue_.value(-1);
        bvalue_.value(-1);
        setValuators();
    }
}

////////////////////////////////////////////////////////////////
// colorChooser()

private final class ColorChip : Widget
{
    ubyte r, g, b;
    this(int X, int Y, int W, int H)
    {
        super(X, Y, W, H);
        box(Boxtype.engravedFrame);
    }
    protected override void draw()
    {
        if ((damage() & damageAll) != 0) drawBox();
        fl_rectf(x() + fl.core.boxDx(box()), y() + fl.core.boxDy(box()),
            w() - fl.core.boxDw(box()), h() - fl.core.boxDh(box()), rgbColor(r, g, b));
    }
}

/**
 * Pops up a window to let the user pick an arbitrary RGB color.
 * Returns 1 if the user confirms the selection (updating r/g/b), or 0
 * if they cancel or close the window (r/g/b left unchanged). Color
 * components are in the range 0.0 to 1.0. cmode optionally sets the
 * initial display mode (see ColorChooser.mode()); -1 (default) means
 * rgb mode.
 */
int colorChooser(string name, ref double r, ref double g, ref double b, int cmode = -1)
{
    import fl.group : FlGroup;

    int ret = 0;
    FlGroup.current(null);
    auto window = new Window(215, 200, name);
    // Deterministic destruction, matching every dialog in fl.ask.d
    // (`scope(exit) destroy(msg);`) -- relying on eventual,
    // nondeterministic GC finalization instead risks an
    // InvalidMemoryOperationError (see fl.tooltip.exit()'s own doc
    // comment for the mechanism); destroying it here removes that
    // reliance for this dialog specifically.
    scope (exit) destroy(window);
    window.callback((w) { ret = 0; w.hide(); });
    auto chooser = new ColorChooser(10, 10, 195, 115);
    auto okColor = new ColorChip(10, 130, 95, 25);
    auto okButton = new ReturnButton(10, 165, 95, 25, ok);
    okButton.callback((w) { ret = 1; w.window().hide(); });
    auto cancelColor = new ColorChip(110, 130, 95, 25);
    cancelColor.r = cast(ubyte)(255 * r + .5);
    okColor.r = cancelColor.r;
    okColor.g = cancelColor.g = cast(ubyte)(255 * g + .5);
    okColor.b = cancelColor.b = cast(ubyte)(255 * b + .5);
    auto cancelButton = new Button(110, 165, 95, 25, fl_cancel);
    cancelButton.callback((w) { ret = 0; w.window().hide(); });
    window.resizable(chooser);
    chooser.rgb(r, g, b);
    chooser.callback((w)
    {
        auto c = cast(ColorChooser) w;
        okColor.r = cast(ubyte)(255 * c.r() + .5);
        okColor.g = cast(ubyte)(255 * c.g() + .5);
        okColor.b = cast(ubyte)(255 * c.b() + .5);
        okColor.damage(damageExpose);
    });
    if (cmode != -1) chooser.mode(cmode);
    window.end();
    window.setModal();
    window.hotspot(window);
    window.show();
    while (window.shown()) fl.core.wait();
    if (ret)
    {
        r = chooser.r();
        g = chooser.g();
        b = chooser.b();
    }
    return ret;
}

/**
 * Same as the double overload, but color components are in the range
 * 0 to 255.
 */
int colorChooser(string name, ref ubyte r, ref ubyte g, ref ubyte b, int cmode = -1)
{
    double dr = r / 255.0, dg = g / 255.0, db = b / 255.0;
    if (colorChooser(name, dr, dg, db, cmode))
    {
        r = cast(ubyte)(255 * dr + .5);
        g = cast(ubyte)(255 * dg + .5);
        b = cast(ubyte)(255 * db + .5);
        return 1;
    }
    return 0;
}

unittest
{
    // hsv2rgb()/rgb2hsv() round-tripping at the six primary/secondary
    // hues plus black/white/gray -- the same reference points FLTK's
    // own math is built around (each integer H selects one branch of
    // hsv2rgb()'s switch).
    import std.math : isClose;

    void checkRoundTrip(double r, double g, double b)
    {
        // rgb2hsv() is ref, not out (see its own doc comment) -- callers
        // must pre-initialize, matching every real call site.
        double h = 0, s = 0, v = 0;
        ColorChooser.rgb2hsv(r, g, b, h, s, v);
        double r2, g2, b2;
        ColorChooser.hsv2rgb(h, s, v, r2, g2, b2);
        assert(isClose(r, r2, 1e-9, 1e-9));
        assert(isClose(g, g2, 1e-9, 1e-9));
        assert(isClose(b, b2, 1e-9, 1e-9));
    }

    checkRoundTrip(1, 0, 0); // red
    checkRoundTrip(1, 1, 0); // yellow
    checkRoundTrip(0, 1, 0); // green
    checkRoundTrip(0, 1, 1); // cyan
    checkRoundTrip(0, 0, 1); // blue
    checkRoundTrip(1, 0, 1); // magenta
    checkRoundTrip(0, 0, 0); // black
    checkRoundTrip(1, 1, 1); // white
    checkRoundTrip(0.5, 0.5, 0.5); // gray

    // black/white: hsv2rgb() takes the S<5e-6 shortcut branch directly.
    double r, g, b;
    ColorChooser.hsv2rgb(0, 0, 0, r, g, b);
    assert(r == 0 && g == 0 && b == 0);
    ColorChooser.hsv2rgb(0, 0, 1, r, g, b);
    assert(r == 1 && g == 1 && b == 1);
}

unittest
{
    // tohs(): the circular hue-wheel coordinate mapping. Center of the
    // box (x=y=0.5) is the wheel's origin -- zero saturation, any hue.
    double h, s;
    tohs(0.5, 0.5, h, s);
    assert(s < 1e-9);

    // Straight right from center (x=1, y=0.5) is hue 0 (red), full
    // saturation -- matches FLTK's atan2(0,1)==0 exactly.
    tohs(1.0, 0.5, h, s);
    assert(h < 1e-9 || h > 6.0 - 1e-9);
    import std.math : isClose;

    assert(isClose(s, 1.0, 1e-9, 1e-9));

    // A far corner clamps saturation to 1 rather than exceeding it.
    tohs(1.0, 1.0, h, s);
    assert(s == 1.0);
}

unittest
{
    // ColorChooser.hsv()/rgb(): both report whether the value actually
    // changed (0 == unchanged, matching FLTK's own change-detection
    // return convention used to decide whether to fire a callback).
    import fl.group : FlGroup;

    FlGroup.current(null);
    auto c = new ColorChooser(0, 0, 195, 115);
    scope (exit) FlGroup.current(null);

    assert(c.r() == 0 && c.g() == 0 && c.b() == 0);

    assert(c.rgb(1, 0, 0) == 1);
    assert(c.rgb(1, 0, 0) == 0); // no-op, unchanged
    assert(c.r() == 1 && c.g() == 0 && c.b() == 0);

    assert(c.hsv(c.hue(), c.saturation(), c.value()) == 0); // no-op
    assert(c.hsv(2.0, 1.0, 1.0) == 1);
    assert(isCloseColor(c.r(), 0) && isCloseColor(c.g(), 1) && isCloseColor(c.b(), 0));
}

version (unittest) private bool isCloseColor(double a, double b)
{
    import std.math : abs;

    return abs(a - b) < 1e-9;
}
