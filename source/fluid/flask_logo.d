/*
 * Fluid's logo, the fldtk logo (`artwork/fldtk-logo.svg`): a lab flask
 * of blue liquid labelled "fldtk" with bubbles rising out of it, as SVG.
 * It is the window icon (`fluid_icon.fl`) and the About box's animation
 * (`about_panel.fl`); drawn by `fl.svg_image.SvgImage`, it stays sharp at
 * any size, and the bubbles move smoothly.
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

    // "fldtk" in DejaVu Sans Bold, as outlines (nanosvg draws no text),
    // the same as artwork/fldtk-logo.svg: dark grey with a red "d".
    static immutable string[2][] word = [
        ["#333333", "m 40.791586,89.017251 v 3.668891 h -3.091237 q -1.186535,0 -1.654904,0.437145 -0.468369,0.421532 -0.468369,1.483169 v 1.21776 h 4.777365 v 3.99675 H 35.577076 V 113.31 H 29.987871 V 99.820966 H 27.20888 v -3.99675 h 2.778991 v -1.21776 q 0,-2.857052 1.592455,-4.215322 1.592455,-1.373883 4.933488,-1.373883 z"], // f
        ["#333333", "m 42.09588,89.017251 h 5.589205 V 113.31 H 42.09588 Z"], // l
        ["#b03931", "m 63.852294,98.384634 v -9.367383 h 5.62043 V 113.31 h -5.62043 v -2.5292 q -1.155311,1.54562 -2.544806,2.26379 -1.389495,0.71816 -3.216135,0.71816 -3.231747,0 -5.308183,-2.56041 -2.076437,-2.57603 -2.076437,-6.61962 0,-4.04359 2.076437,-6.604006 2.076436,-2.57603 5.308183,-2.57603 1.811028,0 3.200523,0.733778 1.405107,0.718166 2.560418,2.248172 z M 60.16779,109.70356 q 1.795415,0 2.732153,-1.31144 0.952351,-1.31143 0.952351,-3.8094 0,-2.49797 -0.952351,-3.8094 -0.936738,-1.311437 -2.732153,-1.311437 -1.779803,0 -2.732153,1.311437 -0.936739,1.31143 -0.936739,3.8094 0,2.49797 0.936739,3.8094 0.95235,1.31144 2.732153,1.31144 z"], // d
        ["#333333", "m 79.84777,90.859503 v 4.964713 h 5.760941 v 3.99675 H 79.84777 v 7.415844 q 0,1.21776 0.483982,1.65491 0.483981,0.42153 1.920313,0.42153 h 2.872664 V 113.31 h -4.792977 q -3.309809,0 -4.699304,-1.37389 -1.373883,-1.38949 -1.373883,-4.6993 v -7.415844 h -2.77899 v -3.99675 h 2.77899 v -4.964713 z"], // t
        ["#333333", "m 87.927803,89.017251 h 5.589206 v 13.223619 l 6.432269,-6.416654 H 106.444 l -8.539934,8.024724 9.211264,9.46106 h -6.77574 l -6.822581,-7.29095 V 113.31 h -5.589206 z"], // k
    ];
    foreach (glyph; word)
        s ~= `<path d="` ~ glyph[1] ~ `" fill="` ~ glyph[0]
            ~ `" transform="scale(0.98314255,1.0171465)"/>`;

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
