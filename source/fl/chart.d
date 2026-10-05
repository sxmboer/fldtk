/*
 * Ported from FL/Fl_Chart.H + src/Fl_Chart.cxx (FLTK 1.5.0). FLTK's own doc comment: "displays simple
 * charts. It is provided for Forms compatibility."
 *
 * Faithful, complete port of the data-management API (add()/insert()/
 * replace()/clear()/bounds()/maxsize()/size()) and all 7 chart-type
 * draw routines (bar/horizontal-bar/line/fill/spike/pie/special-pie).
 *
 * Storage simplification: FLTK's `entries` is a manually
 * calloc()/realloc()'d C array with separate `numb`/`sizenumb`
 * bookkeeping purely to amortize growth -- a D dynamic array
 * (`ChartEntry[]`) already does that for free, so `sizenumb` (capacity
 * tracking) isn't ported at all; `numb` collapses to `entries_.length`.
 * `maxnumb` *is* ported faithfully -- it's a real, user-visible
 * behavior (a sliding-window cap on displayed entries), not a memory
 * detail: add() past the cap drops the *oldest* entry (a memmove
 * shift), while insert() past the cap silently drops the *newest*
 * (FLTK's insert() only grows numb "if (numb<maxnumb ||
 * maxnumb==0)", so the shift's last write lands one slot past what's
 * ever displayed) -- both asymmetries are preserved here.
 *
 * Needed one new fl.draw primitive: the vertex-path
 * fl_arc(double,double,double,double,double), for the pie/special-pie
 * wedges (draw_piechart()) -- see that function's own doc comment in
 * fl.draw for what it does and how it's simplified relative to
 * FLTK. Also promoted fl.draw's previously-private flBorderBox()
 * (backing the borderBox boxtype) to a public rectbound() -- this
 * is fl.chart's first caller of it as the standalone primitive
 * FLTK itself is (draw_barchart()/draw_horbarchart() call it
 * directly, not through a boxtype).
 */
module fl.chart;

import fl.enumerations;
import fl.core;
import fl.widget : Widget;
import fldraw = fl.draw;

import std.math : rint, PI, cos, sin;

/// Values for type(); mirrors Fl_Chart.H's #defines.
enum ubyte barChart = 0;
enum ubyte horbarChart = 1;
enum ubyte lineChart = 2;
enum ubyte fillChart = 3;
enum ubyte filledChart = fillChart; /// for compatibility, matching FLTK's FL_FILLED_CHART alias
enum ubyte spikeChart = 4;
enum ubyte pieChart = 5;
enum ubyte specialpieChart = 6;

/// Max label length for a chart entry (FL_CHART_LABEL_MAX FLTK) --
/// kept only as the truncation limit add()/insert()/replace() apply to
/// str, matching FLTK's fixed-size `char str[]` buffer; a D
/// `string` entry itself has no such limit otherwise.
private enum chartLabelMax = 18;

private struct ChartEntry
{
    double val = 0;
    Color col = 0;
    string str;
}

private string truncateLabel(string str)
{
    return str.length > chartLabelMax ? str[0 .. chartLabelMax] : str;
}

class Chart : Widget
{
    private
    {
        ChartEntry[] entries_;
        int maxnumb_;
        double min_ = 0, max_ = 0;
        bool autosize_ = true;
        Font textfont_;
        Fontsize textsize_;
        Color textcolor_;
    }

    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
        box(Boxtype.borderBox);
        alignment(alignBottom);
        maxnumb_ = 0;
        autosize_ = true;
        min_ = max_ = 0;
        textfont_ = helvetica;
        textsize_ = 10;
        textcolor_ = foregroundColor;
    }

    /// Removes all values from the chart.
    void clear()
    {
        entries_.length = 0;
        min_ = max_ = 0;
        redraw();
    }

    /// Adds a data value, with optional label and color, to the
    /// chart. Past maxsize(), drops the *oldest* entry to make room.
    void add(double val, string str = null, Color col = 0)
    {
        if (entries_.length >= maxnumb_ && maxnumb_ > 0)
            entries_ = entries_[1 .. $];
        entries_ ~= ChartEntry(val, col, truncateLabel(str));
        redraw();
    }

    /// Inserts a data value at 1-based position ind. Past maxsize(),
    /// silently drops what would otherwise be the *newest* entry
    /// (matching FLTK's asymmetry with add() above -- see the
    /// module comment).
    void insert(int ind, double val, string str = null, Color col = 0)
    {
        if (ind < 1 || ind > cast(int) entries_.length + 1) return;

        auto e = ChartEntry(val, col, truncateLabel(str));
        if (entries_.length < maxnumb_ || maxnumb_ == 0)
            entries_ = entries_[0 .. ind - 1] ~ e ~ entries_[ind - 1 .. $];
        else
            entries_ = entries_[0 .. ind - 1] ~ e ~ entries_[ind - 1 .. $ - 1];
        redraw();
    }

    /// Replaces the data value at 1-based position ind.
    void replace(int ind, double val, string str = null, Color col = 0)
    {
        if (ind < 1 || ind > cast(int) entries_.length) return;
        entries_[ind - 1] = ChartEntry(val, col, truncateLabel(str));
        redraw();
    }

    /// Gets the lower/upper bounds of the chart values. Two plain
    /// getters rather than FLTK's out-param-style
    /// `bounds(double*, double*)` -- a same-arity `bounds(out double,
    /// out double)` overload alongside the setter below turned out to
    /// be ambiguous at the call site in D (passing plain, non-`out`-
    /// declared `double` locals matches both overloads, and D quietly
    /// picked the setter instead of the getter in testing -- caught by
    /// a failing unittest, not a compile error). Plain getters sidestep
    /// the ambiguity entirely and read more idiomatically in D anyway.
    double boundsMin() const { return min_; }
    double boundsMax() const { return max_; } /// ditto

    /// Sets the lower/upper bounds of the chart values.
    void bounds(double a, double b)
    {
        min_ = a;
        max_ = b;
        redraw();
    }

    /// Number of data values currently in the chart.
    int size() const { return cast(int) entries_.length; }

    /// Same as Widget.size(w, h) -- FLTK re-declares this only to
    /// disambiguate from the data-count size() just above (the same
    /// C++ name-hiding FLTK always needs when a subclass adds an
    /// overload set under a base-class method's name); already covered
    /// here by aliasing the base setter in, see below.
    alias size = Widget.size;

    /// Gets the maximum number of data values kept; 0 means unlimited.
    int maxsize() const { return maxnumb_; }

    /// Sets the maximum number of data values kept, trimming down to
    /// the most recent maxsize() entries if already over the new cap.
    void maxsize(int m)
    {
        if (m < 0) return;
        maxnumb_ = m;
        if (cast(int) entries_.length > maxnumb_)
        {
            entries_ = entries_[$ - maxnumb_ .. $];
            redraw();
        }
    }

    Font textfont() const { return textfont_; }
    void textfont(Font f) { textfont_ = f; }

    Fontsize textsize() const { return textsize_; }
    void textsize(Fontsize s) { textsize_ = s; }

    Color textcolor() const { return textcolor_; }
    void textcolor(Color c) { textcolor_ = c; }

    bool autosize() const { return autosize_; }
    void autosize(bool n) { autosize_ = n; }

    override void draw()
    {
        drawBox();
        Boxtype b = box();
        int xx = x() + fl.core.boxDx(b);
        int yy = y() + fl.core.boxDy(b);
        int ww = w() - fl.core.boxDw(b);
        int hh = h() - fl.core.boxDh(b);
        fldraw.pushClip(xx, yy, ww, hh);

        ww--; hh--; // adjust for line thickness

        if (min_ >= max_)
        {
            min_ = max_ = 0.0;
            foreach (e; entries_)
            {
                if (e.val < min_) min_ = e.val;
                if (e.val > max_) max_ = e.val;
            }
        }

        fldraw.fl_font(textfont_, textsize_);

        switch (type())
        {
        case barChart:
            drawBarchart(xx, yy, ww + 1, hh, entries_, min_, max_, autosize_, maxnumb_, textcolor_);
            break;
        case horbarChart:
            drawHorbarchart(xx, yy, ww, hh + 1, entries_, min_, max_, autosize_, maxnumb_, textcolor_);
            break;
        case pieChart:
            drawPiechart(xx, yy, ww, hh, entries_, false, textcolor_);
            break;
        case specialpieChart:
            drawPiechart(xx, yy, ww, hh, entries_, true, textcolor_);
            break;
        default:
            drawLinechart(type(), xx, yy, ww, hh, entries_, min_, max_, autosize_, maxnumb_, textcolor_);
            break;
        }
        drawLabel();
        fldraw.popClip();
    }
}

private void drawBarchart(int x, int y, int w, int h, ChartEntry[] entries,
    double min, double max, bool autosize, int maxnumb, Color textcolor)
{
    double lh = fldraw.height();
    double incr = (max == min) ? h : h / (max - min);
    int zeroh;
    if ((-min * incr) < lh)
    {
        incr = (h - lh + min * incr) / (max - min);
        zeroh = cast(int)(y + h - lh);
    }
    else
    {
        zeroh = cast(int) rint(y + h + min * incr);
    }
    int bwidth = cast(int) rint(w / cast(double)(autosize ? entries.length : maxnumb));

    fldraw.fl_color(textcolor);
    fldraw.fl_line(x, zeroh, x + w, zeroh);
    if (min == 0.0 && max == 0.0) return;

    foreach (i, e; entries)
    {
        int hh = cast(int) rint(e.val * incr);
        if (hh < 0)
            fldraw.rectbound(x + cast(int) i * bwidth, zeroh, bwidth + 1, -hh + 1, e.col);
        else if (hh > 0)
            fldraw.rectbound(x + cast(int) i * bwidth, zeroh - hh, bwidth + 1, hh + 1, e.col);
    }

    fldraw.fl_color(textcolor);
    foreach (i, e; entries)
        fldraw.fl_draw(e.str, x + cast(int) i * bwidth + bwidth / 2, zeroh, 0, 0, alignTop);
}

private void drawHorbarchart(int x, int y, int w, int h, ChartEntry[] entries,
    double min, double max, bool autosize, int maxnumb, Color textcolor)
{
    double lw = 0.0;
    foreach (e; entries)
    {
        double w1 = fldraw.width(e.str);
        if (w1 > lw) lw = w1;
    }
    if (lw > 0.0) lw += 4.0;

    double incr = (max == min) ? w : w / (max - min);
    int zeroh;
    if ((-min * incr) < lw)
    {
        incr = (w - lw + min * incr) / (max - min);
        zeroh = x + cast(int) rint(lw);
    }
    else
    {
        zeroh = cast(int) rint(x - min * incr);
    }
    int bwidth = cast(int) rint(h / cast(double)(autosize ? entries.length : maxnumb));

    fldraw.fl_color(textcolor);
    fldraw.fl_line(zeroh, y, zeroh, y + h);
    if (min == 0.0 && max == 0.0) return;

    foreach (i, e; entries)
    {
        int ww = cast(int) rint(e.val * incr);
        if (ww > 0)
            fldraw.rectbound(zeroh, y + cast(int) i * bwidth, ww + 1, bwidth + 1, e.col);
        else if (ww < 0)
            fldraw.rectbound(zeroh + ww, y + cast(int) i * bwidth, -ww + 1, bwidth + 1, e.col);
    }

    fldraw.fl_color(textcolor);
    foreach (i, e; entries)
        fldraw.fl_draw(e.str, zeroh - 2, y + cast(int) i * bwidth + bwidth / 2, 0, 0, alignRight);
}

private void drawLinechart(ubyte type, int x, int y, int w, int h, ChartEntry[] entries,
    double min, double max, bool autosize, int maxnumb, Color textcolor)
{
    double lh = fldraw.height();
    double incr = (max == min) ? h - 2.0 * lh : (h - 2.0 * lh) / (max - min);
    int zeroh = cast(int) rint(y + h - lh + min * incr);
    double bwidth = w / cast(double)(autosize ? entries.length : maxnumb);

    foreach (i, e; entries)
    {
        int x0 = x + cast(int) rint((i - .5) * bwidth);
        int x1 = x + cast(int) rint((i + .5) * bwidth);
        int yy0 = i ? zeroh - cast(int) rint(entries[i - 1].val * incr) : 0;
        int yy1 = zeroh - cast(int) rint(e.val * incr);

        if (type == spikeChart)
        {
            fldraw.fl_color(e.col);
            fldraw.fl_line(x1, zeroh, x1, yy1);
        }
        else if (type == lineChart && i != 0)
        {
            fldraw.fl_color(entries[i - 1].col);
            fldraw.fl_line(x0, yy0, x1, yy1);
        }
        else if (type == fillChart && i != 0)
        {
            fldraw.fl_color(entries[i - 1].col);
            if ((entries[i - 1].val > 0.0) != (e.val > 0.0))
            {
                double ttt = entries[i - 1].val / (entries[i - 1].val - e.val);
                int xt = x + cast(int) rint((i - .5 + ttt) * bwidth);
                fldraw.fl_polygon(x0, zeroh, x0, yy0, xt, zeroh);
                fldraw.fl_polygon(xt, zeroh, x1, yy1, x1, zeroh);
            }
            else
            {
                fldraw.fl_polygon(x0, zeroh, x0, yy0, x1, yy1, x1, zeroh);
            }
            fldraw.fl_color(textcolor);
            fldraw.fl_line(x0, yy0, x1, yy1);
        }
    }

    fldraw.fl_color(textcolor);
    fldraw.fl_line(x, zeroh, x + w, zeroh);

    foreach (i, e; entries)
        fldraw.fl_draw(e.str, x + cast(int) rint((i + .5) * bwidth),
            zeroh - cast(int) rint(e.val * incr), 0, 0, e.val >= 0 ? alignBottom : alignTop);
}

private enum arcinc = 2.0 * PI / 360.0;

private void drawPiechart(int x, int y, int w, int h, ChartEntry[] entries,
    bool special, Color textcolor)
{
    double lh = fldraw.height();
    double hDenom = special ? 2.3 : 2.0;
    double rad = (h - 2 * lh) / hDenom / 1.1;
    double xc = x + w / 2.0;
    double yc = y + h - 1.1 * rad - lh;

    double tot = 0.0;
    foreach (e; entries)
        if (e.val > 0.0) tot += e.val;
    if (tot == 0.0) return;
    double incr = 360.0 / tot;

    double curang = 0.0;
    foreach (i, e; entries)
    {
        if (e.val <= 0.0) continue;

        double txc = xc, tyc = yc;
        if (special && i == 0)
        {
            txc += 0.3 * rad * cos(arcinc * (curang + 0.5 * incr * e.val));
            tyc -= 0.3 * rad * sin(arcinc * (curang + 0.5 * incr * e.val));
        }

        fldraw.fl_color(e.col);
        fldraw.beginPolygon();
        fldraw.vertex(txc, tyc);
        fldraw.fl_arc(txc, tyc, rad, curang, curang + incr * e.val);
        fldraw.endPolygon();

        fldraw.fl_color(textcolor);
        fldraw.beginLoop();
        fldraw.vertex(txc, tyc);
        fldraw.fl_arc(txc, tyc, rad, curang, curang + incr * e.val);
        fldraw.endLoop();

        curang += 0.5 * incr * e.val;
        double xl = txc + 1.1 * rad * cos(arcinc * curang);
        fldraw.fl_draw(e.str, cast(int) rint(xl), cast(int) rint(tyc - 1.1 * rad * sin(arcinc * curang)),
            0, 0, xl < txc ? alignRight : alignLeft);
        curang += 0.5 * incr * e.val;
    }
}

unittest
{
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Chart(0, 0, 200, 100);
    assert(c.box() == Boxtype.borderBox);
    assert(c.alignment() == alignBottom);
    assert(c.size() == 0);
    assert(c.maxsize() == 0);
    assert(c.autosize());
    assert(c.textfont() == helvetica);
    assert(c.textsize() == 10);
    assert(c.textcolor() == foregroundColor);

    c.add(5);
    c.add(10, "ten");
    assert(c.size() == 2);

    assert(c.boundsMin() == 0 && c.boundsMax() == 0); // untouched until draw() autosizes them

    c.bounds(0, 100);
    assert(c.boundsMin() == 0 && c.boundsMax() == 100);

    FlGroup.current(null);
}

unittest
{
    // maxsize() caps entries, keeping the most recent ones.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Chart(0, 0, 200, 100);
    c.maxsize(3);
    c.add(1);
    c.add(2);
    c.add(3);
    c.add(4); // past cap: drops the oldest (1)
    assert(c.size() == 3);

    FlGroup.current(null);
}

unittest
{
    // insert()/replace() with 1-based indices; out-of-range is a no-op.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Chart(0, 0, 200, 100);
    c.add(1);
    c.add(3);
    c.insert(2, 2); // between the two existing entries
    assert(c.size() == 3);

    c.replace(2, 99);
    assert(c.size() == 3); // replace never changes the count

    c.insert(0, 5); // out of range: no-op
    c.insert(100, 5); // out of range: no-op
    assert(c.size() == 3);

    FlGroup.current(null);
}

unittest
{
    // clear() resets both entries and bounds.
    import fl.group : FlGroup;
    FlGroup.current(null);

    auto c = new Chart(0, 0, 200, 100);
    c.add(1);
    c.bounds(0, 10);
    c.clear();
    assert(c.size() == 0);

    assert(c.boundsMin() == 0 && c.boundsMax() == 0);

    FlGroup.current(null);
}

unittest
{
    // draw() calls into fl.draw's real-on-Linux-only primitives, which
    // no-op safely without an open display (same pattern as
    // fl.round_button's draw() unittest) -- exercise every chart type.
    import fl.group : FlGroup;
    FlGroup.current(null);

    foreach (t; [barChart, horbarChart, lineChart, fillChart, spikeChart, pieChart, specialpieChart])
    {
        auto c = new Chart(0, 0, 200, 100);
        c.type(t);
        c.add(5, "a");
        c.add(-3, "b");
        c.add(8, "c");
        c.draw();
    }

    FlGroup.current(null);
}
