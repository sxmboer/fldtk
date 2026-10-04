/*
 * Ported from FL/Fl_Multi_Label.H + src/Fl_Multi_Label.cxx (FLTK
 * 1.5.0). Lets a widget's label be built from two side-by-side parts
 * -- labela drawn first, labelb immediately after it (to the right,
 * or above/below/etc. depending on alignment) -- so more than one
 * label "kind" can share a single widget label slot. Chaining labelb
 * (or labela) to another MultiLabel gives an arbitrarily long
 * left-to-right sequence.
 *
 * FLTK stores labela/labelb as a single `const char*`,
 * reinterpreted per typea/typeb as literal text, an `Fl_Image*`, or a
 * chained `Fl_Multi_Label*` -- a tagged-union-via-pointer-cast trick
 * that only works because C++ doesn't check what a `const char*`
 * actually points to (`Fl_Multi_Label::label()` does the cast the
 * other way: `(const char*)this`). D's `Label.text` is a real
 * GC-owned `string`, not a raw pointer that can be punned to another
 * type, so each alternative gets its own typed field here instead of
 * overloading one slot -- a tagged union in spirit, not in memory
 * layout. See fl.widget's `Label.multi` field (the new slot this
 * plugs into) and `Widget.label(MultiLabel)` (the new setter, since a
 * class reference can't be smuggled through `label(Labeltype,
 * string)`'s `string` parameter the way a pointer can through
 * FLTK's `const char*`).
 *
 * Working end-to-end: text parts, image parts, and chained-
 * MultiLabel parts all draw/measure real pixels. `part()` builds a
 * local `Label` copy per part (letting its own `draw()`/`measure()`
 * dispatch on type, exactly like `Fl_Label::draw()` does FLTK) and
 * leaves `typeA`/`typeB` at their default `normalLabel` unless a
 * caller overrides them -- `Widget.Label.measure()`/`draw()`'s
 * `normalLabel` branch already handles a non-null `image` field
 * generically, so an image-only or image+text part needed no
 * `MultiLabel`-specific drawing code at all (see this module's own
 * tests). A chained `multiLabel` part recurses correctly and works the
 * same way, text and image parts alike.
 *
 * label(Fl_Menu_Item*) -- FLTK's other association method, and
 * its headline real-world use (icon+text menu items) -- is ported too,
 * as `fl.menu_item.MenuItem.multiLabel()`.
 * Real-world use: `fluid.gui_main`'s `&New` menu icons, via
 * `fl.menu_.Menu_.multiLabel(int, MultiLabel)`.
 */
module fl.multi_label;

import fl.widget : Widget, Label;
import fl.enumerations : Labeltype, Align, alignTop, alignBottom, alignLeft, alignRight;
import fl.image : Image;

class MultiLabel
{
    string textA, textB;
    Image imageA, imageB;
    MultiLabel multiA, multiB;
    Labeltype typeA = Labeltype.normalLabel;
    Labeltype typeB = Labeltype.normalLabel;

    /// Builds the Label a part (labela/labelb) draws/measures as: a
    /// copy of outer (so font/size/color/margins carry over, matching
    /// FLTK's `Fl_Label local = *o;`) with value/type swapped in.
    private static Label part(const(Label)* outer, string text, const(Image) image,
        const(MultiLabel) multi, Labeltype type)
    {
        Label local = cast(Label) *outer;
        local.text = text;
        local.image = cast(Image) image;
        local.multi = cast(MultiLabel) multi;
        local.type = type;
        return local;
    }

    /// Ported from multi_labeltype() (src/Fl_Multi_Label.cxx). Draws
    /// labela at (x,y,w,h), then shrinks the box by however much
    /// space labela measured at (on whichever edge alignment pushes
    /// labela against) and draws labelb in what's left.
    void draw(int x, int y, int w, int h, Align a, const(Label)* outer) const
    {
        auto local = part(outer, textA, imageA, multiA, typeA);
        int W = w, H = h;
        local.measure(W, H);
        local.draw(x, y, w, h, a);
        if (a & alignBottom) h -= H;
        else if (a & alignTop) { y += H; h -= H; }
        else if (a & alignRight) w -= W;
        else if (a & alignLeft) { x += W; w -= W; }
        else { int d = (h + H) / 2; y += d; h -= d; }
        local = part(outer, textB, imageB, multiB, typeB);
        local.draw(x, y, w, h, a);
    }

    /// Ported from multi_measure() (src/Fl_Multi_Label.cxx). FLTK's
    /// own doc comment caveat applies verbatim here too: "measurement
    /// is only correct for left-to-right appending."
    void measure(out int w, out int h, const(Label)* outer) const
    {
        auto local = part(outer, textA, imageA, multiA, typeA);
        local.measure(w, h);
        local = part(outer, textB, imageB, multiB, typeB);
        int W = 0, H = 0;
        local.measure(W, H);
        w += W;
        if (H > h) h = H;
    }

    /**
     * Associates this MultiLabel with widget o: draws/measures as
     * labela then labelb from now on. Ported from
     * Fl_Multi_Label::label(Fl_Widget*).
     */
    void label(Widget o)
    {
        o.label(this);
    }
}

unittest
{
    import fl.group : FlGroup;
    import fl.box : Box;
    import fl.enumerations : Boxtype;
    import fl.draw : resetForTest;

    FlGroup.current(null);
    // See fl.draw.resetForTest()'s own doc comment: without this, an
    // earlier-run fl.core clipboard test can leave a real display/font
    // connection open for the rest of this `dub test` process, silently
    // turning the "headless fallback width" this test asserts below
    // into a real (and unpredictable) measured width instead.
    resetForTest();

    auto ml = new MultiLabel();
    ml.textA = "AB"; // 2 chars -> headless fallback width 2*6 = 12
    ml.textB = "XYZ"; // 3 chars -> headless fallback width 3*6 = 18

    auto b = new Box(Boxtype.noBox, 0, 0, 100, 20, null);
    ml.label(b);

    assert(b.labeltype() == Labeltype.multiLabel);
    assert(b.labelMulti() is ml);

    int w, h;
    b.measureLabel(w, h);
    assert(w == 12 + 18);
    assert(h == b.labelsize() + 4); // headless fl_height() fallback

    b.draw(); // headless-safe: just confirm it doesn't throw

    FlGroup.current(null);
}

unittest
{
    // Chained MultiLabel: labelb of the outer one is itself a
    // MultiLabel (typeB == multiLabel), mirroring FLTK's "chain up
    // a series of label elements" doc comment.
    import fl.group : FlGroup;
    import fl.box : Box;
    import fl.enumerations : Boxtype;

    FlGroup.current(null);

    auto inner = new MultiLabel();
    inner.textA = "CD"; // 2 chars -> 12px
    inner.textB = "E"; // 1 char -> 6px

    auto outer = new MultiLabel();
    outer.textA = "AB"; // 2 chars -> 12px
    outer.typeB = Labeltype.multiLabel;
    outer.multiB = inner;

    auto b = new Box(Boxtype.noBox, 0, 0, 100, 20, null);
    outer.label(b);

    int w, h;
    b.measureLabel(w, h);
    assert(w == 12 + (12 + 6)); // outer.textA + (inner.textA + inner.textB)

    b.draw(); // headless-safe: just confirm it doesn't throw

    FlGroup.current(null);
}

unittest
{
    // No MultiLabel assigned yet (multi is null): measure()/draw() are
    // safe no-ops, matching a plain empty-text Label.
    Label l;
    l.type = Labeltype.multiLabel;

    int w, h;
    l.measure(w, h);
    assert(w == 0 && h == 0);

    l.draw(0, 0, 50, 20, Align.init); // just confirm it doesn't throw
}

unittest
{
    // An image-part MultiLabel draws/measures real pixels: part()
    // defaults typeA/typeB to Labeltype.normalLabel, and
    // Widget.Label.measure()/draw()'s normalLabel branch already
    // handles a non-null `image` field generically, via
    // fl.image's Bitmap/Image.draw() -- no MultiLabel-
    // specific code is needed here at all.
    import fl.group : FlGroup;
    import fl.box : Box;
    import fl.bitmap : Bitmap;
    import fl.enumerations : Boxtype;
    import fl.draw : resetForTest;

    FlGroup.current(null);
    resetForTest();

    auto ml = new MultiLabel();
    ml.textA = ""; // image-only part
    ml.imageA = new Bitmap([0, 0, 0, 0, 0, 0, 0, 0], 8, 8);
    ml.textB = "X"; // 1 char -> headless fallback width 6

    auto b = new Box(Boxtype.noBox, 0, 0, 100, 20, null);
    ml.label(b);

    int w, h;
    b.measureLabel(w, h);
    assert(w == 8 + 6); // imageA's real width (8px) + textB's width
    assert(h >= 8); // imageA's real height (8px) contributes for real

    b.draw(); // headless-safe: just confirm it doesn't throw

    FlGroup.current(null);
}
