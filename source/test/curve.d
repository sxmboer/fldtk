// D transliteration of FLTK's test/curve.cxx.
// Build: rdmd buildsamples.d test curve
import fl;

double[9] args = [20, 20, 50, 200, 100, 20, 200, 200, 0];
string[9] name = ["X0", "Y0", "X1", "Y1", "X2", "Y2", "X3", "Y3", "rotate"];

bool points;

class Drawing : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    override void draw()
    {
        pushClip(x(), y(), w(), h());
        fl_color(dark3);
        fl_rectf(x(), y(), w(), h());
        pushMatrix();
        if (args[8])
        {
            fl_translate(x() + w() / 2.0, y() + h() / 2.0);
            fl_rotate(args[8]);
            fl_translate(-(x() + w() / 2.0), -(y() + h() / 2.0));
        }
        fl_translate(x(), y());
        if (!points)
        {
            fl_color(white);
            beginComplexPolygon();
            fl.draw.curve(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
            endComplexPolygon();
        }
        fl_color(black);
        beginLine();
        vertex(args[0], args[1]);
        vertex(args[2], args[3]);
        vertex(args[4], args[5]);
        vertex(args[6], args[7]);
        endLine();
        fl_color(points ? white : red);
        if (points) beginPoints(); else beginLine();
        fl.draw.curve(args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
        if (points) endPoints(); else endLine();
        popMatrix();
        popClip();
    }
}

Drawing d;

void pointsCb(Widget o)
{
    points = (cast(ToggleButton) o).value();
    d.redraw();
}

// Named cmdArgs, not args -- this file already has a module-level
// `double[9] args` (the curve control points, matching FLTK's own
// global of the same name) that a same-named main() parameter would
// shadow.
void main(string[] cmdArgs)
{
    auto window = new DoubleWindow(300, 555);
    auto drawing = new Drawing(10, 10, 280, 280);
    d = drawing;

    int y = 300;
    for (int n = 0; n < 9; n++)
    {
        auto s = new HorValueSlider(50, y, 240, 25, name[n]);
        y += 25;
        s.minimum(0);
        s.maximum(280);
        if (n == 8) s.maximum(360);
        s.step(1);
        s.value(args[n]);
        s.alignment(alignLeft);
        // Ported from curve.cxx's `slider_cb(Fl_Widget* o, void* v)`:
        // FLTK derives which args[] slot to update from `v`, a raw
        // index smuggled through Fl_Callback's void* user_data
        // (`s->callback(slider_cb, (void*)(fl_intptr_t)n)`); this
        // port's Callback (`void delegate(Widget)`, see fl.widget's own
        // module comment) has no such side-channel. The index is
        // derived the same way `v` served FLTK but from data
        // already on the widget for an unrelated reason: the slider's
        // own label (set to name[n] just above, same as FLTK) is
        // looked back up in name[] to find its position. This closure
        // does NOT capture `n` -- only `name`/`args`/`d`, the same
        // module-level globals on every iteration -- so, unlike the
        // very first version of this file, it's immune to the D
        // closure-loop-variable trap and can be written directly
        // inline here, exactly like FLTK's own callback shape.
        s.callback((w) {
            import std.algorithm.searching : countUntil;
            auto sl = cast(Slider) w;
            auto idx = name[].countUntil(sl.label());
            args[idx] = sl.value();
            d.redraw();
        });
    }
    auto but = new ToggleButton(50, y, 50, 25, "points");
    but.callback((w) { pointsCb(w); });

    window.end();
    window.show(cmdArgs);
    fl.run();
}
