/*
 * `Fl_Window` (and `Fl_Double_Window`) node -- a container, plus a
 * handful of window-only properties. Ported from FLTK's
 * `Window_Node` (`fluid/nodes/Window_Node.h`/`.cxx`). Started as a
 * Phase 1 subset (enough for `test/fast_slow.fl`: modal/non_modal/
 * xclass/noborder), grown since with `size_range` (FLTK's own `sr_min_w`/`sr_min_h`/
 * `sr_max_w`/`sr_max_h`, matching `size_range {minw minh maxw maxh}`'s
 * own four-int `.fl` shape; FLTK's own `widget_panel.fl` "Size
 * Range:" UI only ever exposes these four fields too, not the dw/dh/
 * aspect-ratio parameters `Fl_Window::size_range()`'s full signature
 * also has, so stopping here matches FLTK's own UI ceiling, not a
 * corner cut below it).
 */
module fluid.window_node;

import std.string : split;
import std.conv : to, ConvException;

import fluid.node;
import fluid.widget_node;
import fluid.project_reader : Reader;

class WindowNode : WidgetNode
{
    bool modal_;
    bool nonModal_;
    bool noBorder_;
    string xclass;

    int sizeRangeMinW, sizeRangeMinH, sizeRangeMaxW, sizeRangeMaxH;
    bool hasSizeRange;

    override bool canHaveChildren() const { return true; }

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "modal":
            modal_ = true;
            return true;
        case "non_modal":
            nonModal_ = true;
            return true;
        case "xclass":
            xclass = r.readValue();
            return true;
        case "noborder":
            // FLTK: the widget panel wires the
            // real "Border" light button in `widget_panel.d`, which
            // needs a real backing field.
            noBorder_ = true;
            return true;
        case "size_range":
        {
            auto parts = split(r.readValue());
            if (parts.length >= 4)
            {
                try
                {
                    sizeRangeMinW = to!int(parts[0]);
                    sizeRangeMinH = to!int(parts[1]);
                    sizeRangeMaxW = to!int(parts[2]);
                    sizeRangeMaxH = to!int(parts[3]);
                    hasSizeRange = true;
                }
                catch (ConvException)
                {
                    // Malformed project file -- leave hasSizeRange
                    // false rather than crash on a corrupt field.
                }
            }
            return true;
        }
        default:
            return super.readProperty(r, name);
        }
    }
}
