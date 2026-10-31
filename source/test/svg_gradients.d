// fldtk test program: SVG gradients in bounding-box units.
// Build: rdmd buildsamples.d test svg_gradients
//
// Each picture is an SvgImage of one wide rectangle with a gradient; the
// label under it says what the gradient should look like.
import fl;

enum w = 220, h = 90;

string svg(string gradient)
{
    return `<svg xmlns="http://www.w3.org/2000/svg" width="220" height="90">`
        ~ `<defs>` ~ gradient ~ `</defs>`
        ~ `<rect x="10" y="10" width="200" height="70" fill="url(#g)" stroke="black"/>`
        ~ `</svg>`;
}

enum stops = `<stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/>`;

immutable string[2][] samples = [
    [`<linearGradient id="g" x1="0" y1="0" x2="1" y2="0">` ~ stops ~ `</linearGradient>`,
     "red at the left, blue at the right"],
    [`<linearGradient id="g" x1="0" y1="0" x2="1" y2="0" gradientTransform="rotate(90)">` ~ stops ~ `</linearGradient>`,
     "rotate(90): red at the top, blue at the bottom"],
    [`<linearGradient id="g" x1="0" y1="0.5" x2="1" y2="0.5" gradientTransform="rotate(45 0.5 0.5)">` ~ stops ~ `</linearGradient>`,
     "rotate(45 0.5 0.5): red top left to blue bottom right, bands along the other diagonal"],
    [`<linearGradient id="g" gradientTransform="scale(0.5)">` ~ stops ~ `</linearGradient>`,
     "scale(0.5): red to blue over the left half, blue after"],
    [`<radialGradient id="g" cx="0.5" cy="0.5" r="0.5">` ~ stops ~ `</radialGradient>`,
     "radial: red centre, an ellipse touching all four sides"],
    [`<radialGradient id="g" cx="0.5" cy="0.5" r="0.5" gradientTransform="translate(0.25 0)">` ~ stops ~ `</radialGradient>`,
     "translate(0.25 0): the same ellipse, centred three quarters across"],
];

void main(string[] args)
{
    int cols = 2;
    int rows = cast(int)((samples.length + cols - 1) / cols);
    auto win = new Window(cols * (w + 20) + 20, rows * (h + 40) + 20, "SVG gradients");
    foreach (i, sample; samples)
    {
        int x = 20 + cast(int)(i % cols) * (w + 20);
        int y = 20 + cast(int)(i / cols) * (h + 40);
        auto box = new Box(x, y, w, h);
        box.image(new SvgImage(null, svg(sample[0])));
        auto label = new Box(x, y + h, w, 30, sample[1]);
        label.labelsize(12);
        label.alignment(alignInside | alignTop | alignWrap);
    }
    win.end();
    win.show(args);
    run();
}
