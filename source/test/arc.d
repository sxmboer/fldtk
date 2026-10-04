// D transliteration of FLTK's test/arc.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh arc
import fl;

double[6] args = [140, 140, 50, 0, 360, 0];
string[6] name = ["X", "Y", "R", "start", "end", "rotate"];

class Drawing : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    override void draw()
    {
        pushClip(x(), y(), w(), h());
        fl_color(dark3);
        fl_rectf(x(), y(), w(), h());
        pushMatrix();
        if (args[5])
        {
            fl_translate(x() + w() / 2.0, y() + h() / 2.0);
            fl_rotate(args[5]);
            fl_translate(-(x() + w() / 2.0), -(y() + h() / 2.0));
        }
        fl_color(white);
        fl_translate(x(), y());
        beginComplexPolygon();
        fl_arc(args[0], args[1], args[2], args[3], args[4]);
        fl_gap();
        fl_arc(140, 140, 20, 0, -360);
        endComplexPolygon();
        fl_color(red);
        beginLine();
        fl_arc(args[0], args[1], args[2], args[3], args[4]);
        endLine();
        popMatrix();
        popClip();
    }
}

Drawing d;

// Named cmdArgs, not args -- this file already has a module-level
// `double[6] args` (the arc parameters, matching FLTK's own global
// of the same name) that a same-named main() parameter would shadow.
void main(string[] cmdArgs)
{
    auto window = new DoubleWindow(300, 500);
    auto drawing = new Drawing(10, 10, 280, 280);
    d = drawing;

    int y = 300;
    for (int n = 0; n < 6; n++)
    {
        auto s = new HorValueSlider(50, y, 240, 25, name[n]);
        y += 25;
        if (n < 3) { s.minimum(0); s.maximum(300); }
        else if (n == 5) { s.minimum(0); s.maximum(360); }
        else { s.minimum(-360); s.maximum(360); }
        s.step(1);
        s.value(args[n]);
        s.alignment(alignLeft);
        // Ported from arc.cxx's `slider_cb(Fl_Widget* o, void* v)`:
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

    window.end();
    window.show(cmdArgs);
    fl.run();
}
