// D transliteration of FLTK's test/pack.cxx.
// Build: rdmd buildsamples.d test pack
//
// FLTK guards this file with two #define's (USE_FLEX, USE_SCROLL) that
// pick between Fl_Pack/Fl_Flex and whether to nest inside Fl_Scroll. The
// committed defaults are USE_FLEX=0, USE_SCROLL=1 (use Fl_Pack, inside
// Fl_Scroll) -- this transliteration follows that compiled-in default path
// only, since the other branch is dead code in the shipped program.
import fl;

Pack pack;
Scroll scroll;

void typeCb(int v)
{
    for (int i = 0; i < pack.children; i++)
    {
        Widget o = pack.child(i);
        o.resize(0, 0, 25, 25);
    }
    pack.type(cast(ubyte) v);

    pack.resize(scroll.x, scroll.y, scroll.w, scroll.h);

    pack.parent.redraw();
    pack.redraw();
}

void spacingCb(ValueSlider o)
{
    int s = cast(int) o.value();
    pack.spacing(s);
    pack.parent.redraw();
}

void main(string[] args)
{
    auto w = new DoubleWindow(360, 370);

    scroll = new Scroll(10, 10, 340, 285);

    int nbuttons = 24;
    pack = new Pack(10, 10, 340, 285);
    pack.box(Boxtype.downFrame);

    // create buttons: position (xx, xx) will be "fixed" by Fl_Pack
    int xx = 35;
    for (int i = 0; i < nbuttons; i++)
    {
        import std.format : format;

        string ltxt = format("b%d", i + 1);
        auto b = new Button(xx, xx, 25, 25);
        b.copyLabel(ltxt);
        xx += 10;
    }

    pack.end();
    w.resizable(pack);

    scroll.end();

    {
        auto o = new LightButton(10, 305, 165, 25, "HORIZONTAL");
        o.type(radioButton);
        o.callback((widget) { typeCb(packHorizontal); });
    }
    {
        auto o = new LightButton(185, 305, 165, 25, "VERTICAL");
        o.type(radioButton);
        o.value(true);
        o.callback((widget) { typeCb(packVertical); });
    }
    {
        auto o = new ValueSlider(100, 335, 250, 25, "Spacing: ");
        o.alignment(alignLeft);
        o.type(horSlider);
        o.range(0, 30);
        o.step(1);
        o.callback((widget) { spacingCb(o); });
    }
    w.end();
    w.sizeRange(300, 300);
    w.show(args);
    fl.run();
}
