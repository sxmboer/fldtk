/*
 * Ported from FL/Fl_Progress.H + src/Fl_Progress.cxx (FLTK 1.5.0,
 * ~/Repositories/fltk). A simple progress bar: a plain `Fl_Widget`
 * subclass (not `Fl_Valuator`-based) holding a `float` value/minimum/
 * maximum, drawn as two clipped regions -- the "filled" portion in
 * selectionColor(), the rest in color() -- so the label (if any) reads
 * correctly in both regions even though each is drawn with different
 * colors underneath it.
 *
 * Faithful, complete port, and draws real pixels entirely now: draw()'s
 * box/label/color calls (drawBox(), fl.widget's drawLabel(), fl.draw's
 * contrast()/inactive()) and its pushClip()/popClip() calls
 * (real now too) are all real, so the two-region (filled-portion-vs-
 * rest) split is actually clipped -- each region confines its drawBox()
 * to its own portion instead of drawing across the widget's full
 * bounds.
 */
module fl.progress;

import fl.enumerations;
import fl.widget : Widget;
import fl.draw;
import fl.core;

class Progress : Widget
{
    private
    {
        float value_, minimum_, maximum_;
    }

    /// The default boxtype is downBox; default colors are
    /// background2Color/yellow (background/progress-fill).
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        alignment(alignInside);
        box(Boxtype.downBox);
        color(background2Color, yellow);
        minimum(0.0f);
        maximum(100.0f);
        value(0.0f);
    }

    void maximum(float v) { maximum_ = v; redraw(); }
    float maximum() const { return maximum_; }

    void minimum(float v) { minimum_ = v; redraw(); }
    float minimum() const { return minimum_; }

    void value(float v) { value_ = v; redraw(); }
    float value() const { return value_; }

    protected:

    override void draw()
    {
        int bx = fl.core.boxDx(box());
        int by = fl.core.boxDy(box());
        int bw = fl.core.boxDw(box());
        int bh = fl.core.boxDh(box());

        int tx = x() + bx;
        int tw = w() - bw;

        int progress;
        if (maximum_ > minimum_)
            progress = cast(int)(w() * (value_ - minimum_) / (maximum_ - minimum_) + 0.5f);
        else
            progress = 0;

        if (progress > 0)
        {
            Color c = labelcolor();
            labelcolor(contrast(labelcolor(), selectionColor()));

            pushClip(x(), y(), progress + bx, h());
            drawBox(box(), x(), y(), w(), h(), activeR() ? selectionColor() : inactive(selectionColor()));
            drawLabel(tx, y() + by, tw, h() - bh);
            popClip();

            labelcolor(c);

            if (progress < w())
            {
                pushClip(tx + progress, y(), w() - progress, h());
                drawBox(box(), x(), y(), w(), h(), activeR() ? color() : inactive(color()));
                drawLabel(tx, y() + by, tw, h() - bh);
                popClip();
            }
        }
        else
        {
            drawBox(box(), x(), y(), w(), h(), activeR() ? color() : inactive(color()));
            drawLabel(tx, y() + by, tw, h() - bh);
        }
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto p = new Progress(0, 0, 200, 20);
    assert(p.box() == Boxtype.downBox);
    assert(p.color() == background2Color);
    assert(p.selectionColor() == yellow);
    assert(p.minimum() == 0.0f);
    assert(p.maximum() == 100.0f);
    assert(p.value() == 0.0f);

    fl.core.resetForTest();
}

unittest
{
    // value()/minimum()/maximum() are plain stored-value setters (no
    // clamping FLTK, so none here either) that each trigger a
    // redraw.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto p = new Progress(0, 0, 200, 20);
    p.value(42.5f);
    assert(p.value() == 42.5f);

    p.maximum(200.0f);
    assert(p.maximum() == 200.0f);

    p.minimum(-10.0f);
    assert(p.minimum() == -10.0f);

    fl.core.resetForTest();
}
