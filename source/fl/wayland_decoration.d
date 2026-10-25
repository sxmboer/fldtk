/*
 * The title bar and frame fldtk draws itself for a window with a border
 * on Wayland, when the compositor leaves decorations to the program
 * (GNOME, Weston). Compositors that draw them (KDE, sway, labwc, ...)
 * are asked to through xdg-decoration, and then nothing here is used.
 * FLTK uses libdecor for both cases; fldtk has no such dependency.
 *
 * This module is the frame's geometry, what is under the pointer, and
 * its drawing (Cairo, with Pango for the title), in the program's own
 * colors. `fl.platform_wayland` gives each decorated window a frame
 * surface, a subsurface below the window's own surface, sized to the
 * window plus the title bar above it and an invisible margin all round
 * that resizes the window; it routes the pointer events on that surface
 * here and moves, resizes, maximizes, minimizes or closes the window.
 *
 * Coordinates here are logical pixels (the compositor's surface units);
 * `scale` is the number of buffer pixels per logical pixel.
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`).
 */
module fl.wayland_decoration;

version (FLDTK_HAVE_WAYLAND):

import fl.cairo_c;
import fl.pango_c;
import fl.pango_c_cairo;
import fl.glib_c : g_object_unref;
import fl.enumerations : backgroundColor, foregroundColor, selectionColor;
import fl.core : getColor;
import std.string : toStringz;

/// The parts of a frame the pointer can be over.
enum Part
{
    none,       // the window's content, or nothing
    title,      // moves the window
    close,
    maximize,
    minimize,
    resizeTop,
    resizeBottom,
    resizeLeft,
    resizeRight,
    resizeTopLeft,
    resizeTopRight,
    resizeBottomLeft,
    resizeBottomRight,
}

/// The state of a window that changes how its frame looks and acts.
struct FrameState
{
    int width, height;  // the window's content, logical pixels
    float zoom = 1;     // fldtk's own scale (Ctrl +/-), which the title bar follows
    bool active;        // has the keyboard focus
    bool maximized;
    bool fullscreen;
    bool tiled;         // against screen edges or other windows
    bool resizable;
    bool canMaximize = true, canMinimize = true; // what the compositor supports
    Part hovered, pressed;
}

/// Height of the title bar.
int titleHeight(const ref FrameState s)
{
    if (s.fullscreen) return 0;
    return cast(int)(28 * s.zoom + 0.5f);
}

/// Width of the invisible margin round the window that resizes it.
int margin(const ref FrameState s)
{
    return s.resizable && !s.maximized && !s.fullscreen && !s.tiled ? 8 : 0;
}

/// Whether the frame shows at all.
bool visible(const ref FrameState s)
{
    return !s.fullscreen;
}

/// Size of the frame surface.
void frameSize(const ref FrameState s, out int w, out int h)
{
    int m = margin(s);
    w = s.width + 2 * m;
    h = s.height + titleHeight(s) + 2 * m;
}

/// Where the frame surface goes, relative to the window's surface.
void framePosition(const ref FrameState s, out int x, out int y)
{
    int m = margin(s);
    x = -m;
    y = -titleHeight(s) - m;
}

private int buttonWidth(const ref FrameState s)
{
    return cast(int)(34 * s.zoom + 0.5f);
}

/// The title-bar buttons, right to left: close, and maximize and
/// minimize where they work.
private Part[] buttons(const ref FrameState s)
{
    Part[] b = [Part.close];
    if (s.resizable && s.canMaximize) b ~= Part.maximize;
    if (s.canMinimize) b ~= Part.minimize;
    return b;
}

/// The rectangle of title-bar button `p` in frame-surface coordinates,
/// or false when the frame has no such button.
private bool buttonRect(const ref FrameState s, Part p, out int x, out int y, out int w, out int h)
{
    int m = margin(s), bw = buttonWidth(s);
    foreach (i, b; buttons(s))
    {
        if (b != p) continue;
        x = m + s.width - cast(int)(i + 1) * bw;
        y = m;
        w = bw;
        h = titleHeight(s);
        return true;
    }
    return false;
}

/// The part of the frame at `(x, y)`, frame-surface coordinates.
Part partAt(const ref FrameState s, int x, int y)
{
    if (!visible(s)) return Part.none;
    int m = margin(s), t = titleHeight(s);
    int gx = x - m, gy = y - m;               // relative to the title bar's top-left
    int gw = s.width, gh = s.height + t;      // the window with its title bar
    bool left = gx < 0, right = gx >= gw, top = gy < 0, bottom = gy >= gh;
    if (left || right || top || bottom)
    {
        if (m == 0) return Part.none;
        enum corner = 16;  // how far along an edge a corner reaches
        bool nearLeft = gx < corner, nearRight = gx >= gw - corner;
        bool nearTop = gy < corner, nearBottom = gy >= gh - corner;
        if ((top && nearLeft) || (left && nearTop)) return Part.resizeTopLeft;
        if ((top && nearRight) || (right && nearTop)) return Part.resizeTopRight;
        if ((bottom && nearLeft) || (left && nearBottom)) return Part.resizeBottomLeft;
        if ((bottom && nearRight) || (right && nearBottom)) return Part.resizeBottomRight;
        if (top) return Part.resizeTop;
        if (bottom) return Part.resizeBottom;
        return left ? Part.resizeLeft : Part.resizeRight;
    }
    if (gy >= t) return Part.none;
    foreach (b; buttons(s))
    {
        int bx, by, bw, bh;
        buttonRect(s, b, bx, by, bw, bh);
        if (x >= bx && x < bx + bw) return b;
    }
    return Part.title;
}

/// A color of the program's color map as Cairo's fractions, shaded
/// towards black (`shade` < 1) or white (`shade` > 1).
private void setColor(cairo_t* cr, uint color, double shade = 1, double alpha = 1)
{
    import fl.enumerations : Color;
    ubyte r, g, b;
    getColor(cast(Color) color, r, g, b);
    double f(ubyte v)
    {
        double d = v / 255.0;
        return shade <= 1 ? d * shade : d + (1 - d) * (shade - 1);
    }
    cairo_set_source_rgba(cr, f(r), f(g), f(b), alpha);
}

/**
 * Draws the frame into `cr`, a surface of the frame's size times
 * `scale`: transparent but for the title bar, its buttons and a line
 * round the window, in the program's background color.
 */
void drawFrame(cairo_t* cr, const ref FrameState s, string title, double scale)
{
    cairo_save(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_rgba(cr, 0, 0, 0, 0);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    cairo_scale(cr, scale, scale);
    if (!visible(s)) { cairo_restore(cr); return; }

    int m = margin(s), t = titleHeight(s), W = s.width;

    // the title bar
    setColor(cr, backgroundColor, s.active ? 0.88 : 1.0);
    cairo_rectangle(cr, m, m, W, t);
    cairo_fill(cr);

    // a line round the window and under the title bar
    cairo_set_line_width(cr, 1);
    setColor(cr, foregroundColor, 1, s.active ? 0.45 : 0.3);
    cairo_rectangle(cr, m - 0.5, m - 0.5, W + 1, s.height + t + 1);
    cairo_stroke(cr);
    cairo_move_to(cr, m, m + t - 0.5);
    cairo_line_to(cr, m + W, m + t - 0.5);
    cairo_stroke(cr);

    // the buttons
    int titleRight = m + W;
    foreach (b; buttons(s))
    {
        int bx, by, bw, bh;
        buttonRect(s, b, bx, by, bw, bh);
        if (bx < titleRight) titleRight = bx;
        if (bx < m) continue; // too narrow a window
        if (s.pressed == b || (s.hovered == b && s.pressed == Part.none))
        {
            if (b == Part.close) setColor(cr, selectionColor, s.pressed == b ? 0.8 : 1);
            else setColor(cr, foregroundColor, 1, s.pressed == b ? 0.25 : 0.12);
            cairo_rectangle(cr, bx, by, bw, bh - 1);
            cairo_fill(cr);
        }
        drawGlyph(cr, b, s, bx + bw / 2.0, by + bh / 2.0);
    }

    // the title, centred in the space left of the buttons
    int pad = cast(int)(10 * s.zoom);
    int textW = titleRight - m - 2 * pad;
    if (title.length && textW > 0)
    {
        PangoLayout* layout = pango_cairo_create_layout(cr);
        PangoFontDescription* desc = pango_font_description_from_string("Sans");
        pango_font_description_set_weight(desc, PANGO_WEIGHT_BOLD);
        pango_font_description_set_absolute_size(desc, 13 * s.zoom * PANGO_SCALE);
        pango_layout_set_font_description(layout, desc);
        pango_font_description_free(desc);
        pango_layout_set_text(layout, title.toStringz, cast(int) title.length);
        pango_layout_set_width(layout, textW * PANGO_SCALE);
        pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
        int tw, th;
        pango_layout_get_pixel_size(layout, &tw, &th);
        double tx = m + (W - tw) / 2.0;            // centred on the window
        if (tx < m + pad) tx = m + pad;
        if (tx + tw > titleRight - pad) tx = titleRight - pad - tw;
        setColor(cr, foregroundColor, 1, s.active ? 1 : 0.5);
        cairo_move_to(cr, tx, m + (t - th) / 2.0);
        pango_cairo_show_layout(cr, layout);
        g_object_unref(layout);
    }
    cairo_restore(cr);
}

/// The symbol of title-bar button `b`, centred on `(cx, cy)`.
private void drawGlyph(cairo_t* cr, Part b, const ref FrameState s, double cx, double cy)
{
    double r = 5 * s.zoom; // half the symbol's size
    bool onAccent = b == Part.close && (s.hovered == b || s.pressed == b);
    if (onAccent) cairo_set_source_rgb(cr, 1, 1, 1);
    else setColor(cr, foregroundColor, 1, s.active ? 0.85 : 0.45);
    cairo_set_line_width(cr, 1.2 * s.zoom);
    switch (b)
    {
        case Part.close:
            cairo_move_to(cr, cx - r, cy - r);
            cairo_line_to(cr, cx + r, cy + r);
            cairo_move_to(cr, cx + r, cy - r);
            cairo_line_to(cr, cx - r, cy + r);
            break;
        case Part.minimize:
            cairo_move_to(cr, cx - r, cy + r - 0.5);
            cairo_line_to(cr, cx + r, cy + r - 0.5);
            break;
        case Part.maximize:
            if (s.maximized)
            {
                // two overlapping squares: restores the window
                double q = r * 0.6;
                cairo_rectangle(cr, cx - r, cy - r + q, 2 * r - q, 2 * r - q);
                cairo_move_to(cr, cx - r + q, cy - r + q);
                cairo_line_to(cr, cx - r + q, cy - r);
                cairo_line_to(cr, cx + r, cy - r);
                cairo_line_to(cr, cx + r, cy + r - q);
                cairo_line_to(cr, cx + r - q, cy + r - q);
            }
            else
                cairo_rectangle(cr, cx - r, cy - r, 2 * r, 2 * r);
            break;
        default:
            break;
    }
    cairo_stroke(cr);
}
