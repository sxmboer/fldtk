// D transliteration of FLTK's test/navigation.cxx.
// Build: rdmd buildsamples.d test navigation
//
// Silly test of navigation keys. This is not a recommended method of
// laying out your panels!
import fl;
import std.random : uniform;

enum int width = 600;
enum int height = 300;
enum int grid = 25;

void main(string[] args)
{
    auto window = new Window(width, height + 40, args.length ? args[0] : null);
    // Include a toggle button to control arrow focus
    auto arrowfocusButt = new LightButton(10, height + 10, 130, 20, " Arrow Focus");
    arrowfocusButt.callback((w) {
        auto b = cast(LightButton) w;
        fl.option(Option.arrowFocus, b.value());
    });
    arrowfocusButt.value(fl.option(Option.arrowFocus)); // use default
    arrowfocusButt.tooltip("Control horizontal arrow key focus navigation behavior.\n"
            ~ "e.g. Fl::OPTION_ARROW_FOCUS");
    window.end(); // don't auto-add children
    for (int i = 0; i < 10000; i++)
    {
        // make up a random size of widget:
        int x = uniform(0, width / grid + 1) * grid;
        int y = uniform(0, height / grid + 1) * grid;
        int w = uniform(0, width / grid + 1) * grid;
        if (w < x)
        {
            w = x - w;
            x -= w;
        }
        else
        {
            w = w - x;
        }
        int h = uniform(0, height / grid + 1) * grid;
        if (h < y)
        {
            h = y - h;
            y -= h;
        }
        else
        {
            h = h - y;
        }
        if (w < grid || h < grid || w < h)
            continue;
        // find where to insert it and see if it intersects something:
        Widget j = null;
        int n;
        for (n = 0; n < window.children(); n++)
        {
            Widget o = window.child(n);
            if (x < o.x() + o.w() && x + w > o.x() && y < o.y() + o.h() && y + h > o.y())
                break;
            if (!j && (y < o.y() || (y == o.y() && x < o.x())))
                j = o;
        }
        // skip if intersection:
        if (n < window.children())
            continue;
        window.insert(new Input(x, y, w, h), j);
    }
    window.show(args);
    fl.run();
}
