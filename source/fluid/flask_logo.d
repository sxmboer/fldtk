/*
 * Fluid's logo, a lab flask of blue liquid labelled "fluid" with bubbles
 * rising out of it, as SVG: the window icon (`fluid_icon.fl`) and the
 * About box's animation (`about_panel.fl`). It is a vector redrawing of
 * FLTK's `fluid/icons/fluid-128.png` and the animated `fluid.animated.gif`
 * the About box shows; drawn by `fl.svg_image.SvgImage`, it stays sharp
 * at any size, and the bubbles move smoothly instead of in five frames.
 *
 * nanosvg draws no text, so the word "fluid" is drawn as strokes: a
 * black outline under a yellow stroke, slanted like FLTK's italic.
 */
module fluid.flask_logo;

import std.format : format;
import std.math : PI, sin;
import std.array : appender;
import fl.image : RGBImage;
import fl.svg_image : SvgImage;
import fl.box : Box;
import fl.core : addTimeout;

/// The flask as SVG text, 128x128 units. `phase` (0 to 1, wrapping)
/// sets where the bubbles are; the window icon uses the default.
string flaskSvg(double phase = 0.3)
{
    auto s = appender!string;
    s ~= `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">`;

    // The flask's inside: a narrow neck widening into a cone.
    enum flask = "M50,6 H78 V50 L117,110 Q122,121 110,121 H18 Q6,121 11,110 L50,50 Z";
    s ~= `<path d="` ~ flask ~ `" fill="#FFFFFF"/>`;
    // The liquid fills the cone up to y = 66.
    s ~= `<path d="M39.6,66 H88.4 L117,110 Q122,121 110,121 H18 Q6,121 11,110 Z" fill="#0080FF"/>`;

    // Bubbles rising from the liquid up through the neck, smaller as
    // they rise; each one is a fixed phase step behind the one before.
    enum count = 5;
    foreach (k; 0 .. count)
    {
        double p = phase + cast(double) k / count;
        p -= cast(long) p;
        double y = 80 - p * 70;
        double x = 64 + 7 * sin(2 * PI * (p * 1.3 + k * 0.37));
        double r = 6 - p * 2.5;
        string color = y > 66 ? "#80C0FF" : "#3399FF";
        s ~= format(`<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>`, x, y, r, color);
    }

    s ~= `<path d="` ~ flask ~ `" fill="none" stroke="#000000" stroke-width="5" stroke-linejoin="round"/>`;

    // "fluid": one skeleton, drawn as a black outline and then in yellow.
    enum word = "M8,-23 Q4,-26 2.5,-20 L1,0 M-2,-14 H7 "  // f
        ~ "M13,-25 V0 "                                   // l
        ~ "M18,-14 V-5 Q18,0 22.5,0 Q27,0 27,-5 V-14 M27,-6 V0 " // u
        ~ "M32,-14 V0 M32,-20.5 V-20 "                    // i
        ~ "M47,-25 V0 M47,-7 Q47,-14 42,-14 Q37,-14 37,-7 Q37,0 42,0 Q47,0 47,-7"; // d
    enum place = `transform="translate(31,110) scale(1.4) skewX(-12)"`;
    s ~= `<path d="` ~ word ~ `" ` ~ place ~ ` fill="none" stroke="#000000" stroke-width="5.4" stroke-linecap="round" stroke-linejoin="round"/>`;
    s ~= `<path d="` ~ word ~ `" ` ~ place ~ ` fill="none" stroke="#FFFF00" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>`;

    s ~= `</svg>`;
    return s[];
}

/// The window icon, at the sizes desktops ask for.
RGBImage[] flaskIcons()
{
    RGBImage[] icons;
    foreach (size; [16, 32, 48, 64, 128, 256])
    {
        auto img = new SvgImage(null, flaskSvg());
        img.resize(size, size);
        icons ~= img;
    }
    return icons;
}

/// Shows the flask in `box`, `size` pixels square, with its bubbles
/// rising while the box is visible.
void animateFlask(Box box, int size)
{
    enum step = 0.04;  // seconds between frames
    enum period = 2.0; // seconds for a bubble to rise
    double phase = 0;

    void show()
    {
        auto img = new SvgImage(null, flaskSvg(phase));
        img.scale(size, size);
        box.image(img);
        box.redraw();
    }

    void tick()
    {
        if (box.visibleR())
        {
            phase += step / period;
            if (phase >= 1) phase -= 1;
            show();
            addTimeout(step, &tick);
        }
        else
            addTimeout(0.25, &tick); // check again for the box being shown
    }

    show();
    addTimeout(step, &tick);
}

unittest
{
    import std.algorithm.searching : canFind;

    auto img = new SvgImage(null, flaskSvg());
    assert(!img.fail());
    assert(img.w() == 128 && img.h() == 128);
    assert(flaskSvg(0.1) != flaskSvg(0.6)); // the bubbles move
    assert(flaskIcons().length == 6);
    assert(flaskIcons()[1].w() == 32);
}
