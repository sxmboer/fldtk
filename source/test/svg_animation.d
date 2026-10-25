// An fldtk demo with no FLTK counterpart: SVG images that move.
// Build: rdmd buildsamples.d test svg_animation
//
// SvgImage draws still SVG images; it plays no SVG animation. To make
// one move, the program writes the SVG text for what should be on
// screen now, turns it into a new SvgImage and shows that, about 30
// times a second. The SVG is drawn at the screen's scale, so it stays
// sharp at any size, and building the text is ordinary D string code,
// so a picture can show any data the program has.
//
// Left: a wind gauge whose needle swings smoothly to the slider's value.
// Right: a sea at sunset, waves rolling and a boat bobbing on them; the
// stronger the wind on the gauge, the higher the waves.
//
// The window is a DoubleWindow: each frame is drawn off screen and shown
// whole, so the picture never flickers while it is being redrawn. Both
// boxes paint their own background, so a new frame never lands on top of
// the old one.
import fl;
import std.array : appender;
import std.format : format;
import std.math : PI, cos, sin;

enum size = 240;        // both pictures are size x size pixels
enum frameTime = 1.0 / 30;

/// The gauge, with its needle at `value` (0 to 100).
string gaugeSvg(double value)
{
    auto s = appender!string;
    s ~= format(`<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 200 200">`, size, size);
    s ~= `<defs><radialGradient id="face" cx="0.5" cy="0.4" r="0.6">`
        ~ `<stop offset="0" stop-color="#4A4A58"/><stop offset="1" stop-color="#16161C"/>`
        ~ `</radialGradient></defs>`;
    s ~= `<circle cx="100" cy="100" r="96" fill="url(#face)" stroke="#9090A0" stroke-width="4"/>`;

    // The scale runs clockwise over 270 degrees, from bottom left
    // (value 0) to bottom right (value 100).
    double angleOf(double v) { return (135 + v * 2.7) * PI / 180; }

    // A colored band under the scale: green, then yellow, then red.
    foreach (band; [[0.0, 60, 0x3CC85A], [60.0, 85, 0xF0C828], [85.0, 100, 0xE83C32]])
    {
        double a0 = angleOf(band[0]), a1 = angleOf(band[1]);
        s ~= format(`<path d="M%.2f,%.2f A78,78 0 %d 1 %.2f,%.2f" fill="none" stroke="#%06X" stroke-width="10"/>`,
            100 + 78 * cos(a0), 100 + 78 * sin(a0), a1 - a0 > PI ? 1 : 0,
            100 + 78 * cos(a1), 100 + 78 * sin(a1), cast(int) band[2]);
    }

    // Ticks: a long one every 10, a short one every 5.
    foreach (i; 0 .. 21)
    {
        double a = angleOf(i * 5);
        double inner = i % 2 == 0 ? 60 : 66;
        s ~= format(`<path d="M%.2f,%.2f L%.2f,%.2f" stroke="#FFFFFF" stroke-width="%s" stroke-linecap="round"/>`,
            100 + inner * cos(a), 100 + inner * sin(a), 100 + 72 * cos(a), 100 + 72 * sin(a),
            i % 2 == 0 ? "3" : "1.5");
    }

    // The needle points right, then is turned to its value.
    double degrees = 135 + value * 2.7;
    s ~= format(`<path d="M100,95 L170,100 L100,105 L88,100 Z" fill="#FF5030" transform="rotate(%.2f 100 100)"/>`, degrees);
    s ~= `<circle cx="100" cy="100" r="9" fill="#D0D0D8" stroke="#606070" stroke-width="2"/>`;
    s ~= `</svg>`;
    return s[];
}

/// A wave's outline, `amplitude` high and `length` long, moved along by
/// `shift`, its crest line at height `level`; filled down to the bottom.
string wavePath(double level, double amplitude, double length, double shift)
{
    auto s = appender!string;
    s ~= format("M0,%.2f", level + amplitude * sin(shift));
    for (int x = 4; x <= 200; x += 4)
        s ~= format(" L%d,%.2f", x, level + amplitude * sin(2 * PI * x / length + shift));
    s ~= " L200,200 L0,200 Z";
    return s[];
}

/// The height of that same wave at `x`.
double waveHeight(double x, double level, double amplitude, double length, double shift)
{
    return level + amplitude * sin(2 * PI * x / length + shift);
}

/// The sea `t` seconds after the start, with the wind at `wind` (0 to
/// 100, as on the gauge): calm at 0, high waves at 100.
string seaSvg(double t, double wind)
{
    double swell = 0.15 + 1.7 * wind / 100; // how much higher than usual the waves are

    auto s = appender!string;
    s ~= format(`<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 200 200">`, size, size);
    s ~= `<defs>`
        ~ `<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">`
        ~ `<stop offset="0" stop-color="#1C2A6C"/><stop offset="0.6" stop-color="#E0607A"/>`
        ~ `<stop offset="1" stop-color="#FFC060"/></linearGradient>`
        ~ `<radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">`
        ~ `<stop offset="0" stop-color="#FFFBD0"/><stop offset="0.7" stop-color="#FFD040"/>`
        ~ `<stop offset="1" stop-color="#FF9030"/></radialGradient>`
        ~ `</defs>`;
    s ~= `<rect width="200" height="200" fill="url(#sky)"/>`;

    // The sun sinks slowly and comes back up.
    double sunY = 112 + 10 * sin(t * 0.3);
    s ~= format(`<circle cx="130" cy="%.2f" r="28" fill="url(#sun)"/>`, sunY);

    // Three waves, the far ones slower and paler, each partly see-through.
    s ~= format(`<path d="%s" fill="#3050A0" fill-opacity="0.85"/>`, wavePath(120, 3 * swell, 70, t * 1.2));
    s ~= format(`<path d="%s" fill="#2848A0" fill-opacity="0.85"/>`, wavePath(134, 5 * swell, 95, -t * 1.6));

    // The boat rides the front wave, tilted to its slope.
    enum level = 150, length = 120;
    double amplitude = 7 * swell;
    double shift = t * 2;
    double bx = 70;
    double by = waveHeight(bx, level, amplitude, length, shift);
    double slope = waveHeight(bx + 1, level, amplitude, length, shift) - by;
    double tilt = slope * 180 / PI;
    s ~= format(`<g transform="translate(%.2f,%.2f) rotate(%.2f)">`, bx, by, tilt);
    s ~= `<path d="M-22,-4 H22 L15,6 H-15 Z" fill="#5A3418" stroke="#2A1608" stroke-width="1.5" stroke-linejoin="round"/>`;
    s ~= `<path d="M0,-4 V-40" stroke="#2A1608" stroke-width="2"/>`;
    s ~= `<path d="M2,-38 L20,-8 H2 Z" fill="#F4F0E4"/>`;
    s ~= `<path d="M-2,-34 L-16,-8 H-2 Z" fill="#E8E0CC"/>`;
    s ~= `</g>`;

    s ~= format(`<path d="%s" fill="#183478" fill-opacity="0.92"/>`, wavePath(level, amplitude, length, shift));
    s ~= `</svg>`;
    return s[];
}

void main(string[] args)
{
    auto window = new DoubleWindow(2 * size + 64, size + 94, "Animated SVG");

    // The gauge is round; its flat box fills the corners around it with
    // the window's color.
    auto gauge = new Box(Boxtype.flatBox, 22, 22, size, size, null);
    auto slider = new HorValueSlider(22, size + 44, size, 25, "Wind");
    slider.bounds(0, 100);
    slider.step(1);
    slider.value(40);

    // A sunken frame around the sea, 2 pixels wide, outside the picture
    // so the picture does not paint over it.
    auto sea = new Box(Boxtype.downFrame, size + 40, 20, size + 4, size + 4, null);

    window.end();

    // Where the needle is drawn; it eases toward the slider, and the
    // waves follow it.
    double needle = 0;
    double t = 0;

    void frame()
    {
        needle += (slider.value() - needle) * 0.12;
        gauge.image(new SvgImage(null, gaugeSvg(needle)));
        gauge.redraw();

        t += frameTime;
        sea.image(new SvgImage(null, seaSvg(t, needle)));
        sea.redraw();

        repeatTimeout(frameTime, &frame);
    }

    frame();
    window.show(args);
    run();
}
