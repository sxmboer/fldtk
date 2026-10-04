/*
 * Common Fl_Widget-level node -- most leaf widget types (Fl_Box,
 * Fl_Slider, Fl_Button, ...) need nothing beyond this; only container/
 * special types (Fl_Window, Fl_Group, ...) get their own subclass.
 * Ported from FLTK's `Widget_Node` (`fluid/nodes/Widget_Node.h`/
 * `.cxx`) -- covers the subset of its large `read_property()` needed
 * by the fldtk-native `.fl` dialect's files so far (grows per future
 * `.fl` file): `fast_slow.fl`/`resize.fl`/`radio.fl`/`inactive.fl`/
 * `valuators.fl`/`CubeViewUI.fl`.
 */
module fluid.widget_node;

import std.string : split;
import std.conv : to, ConvException;

import fluid.node;
import fluid.project_reader : Reader;

class WidgetNode : Node
{
    int x, y, w, h;
    bool hasXywh;

    /// Written to the `.fl` file as the bare flag `private` or
    /// `protected`; `public` (the default) writes nothing.
    Access access = Access.public_;

    string boxtype;      // raw .fl box keyword, e.g. "DOWN_BOX"
    bool hasBoxtype;
    string downBoxtype;
    bool hasDownBoxtype;

    int color = -1;          // raw numeric color index/hex; -1 = unset
    int selectionColor = -1;

    int labelfont = -1;
    int labelsize = -1;
    int labelcolorRaw = -1;
    string labeltype;
    int textsize = -1;
    int textfont = -1;
    int textcolorRaw = -1;
    int vLabelMargin = -1;
    int hLabelMargin = -1;
    int imageSpacing = -1;

    int alignRaw = -1;   // raw numeric FL_ALIGN_* bitmask
    int whenRaw = -1;    // raw numeric FL_WHEN_* bitmask
    string typeWord;     // raw "type" property (e.g. "Double" for a window)

    // "value"/"compact"/"minimum"/"maximum"/"step" are widget-class-
    // specific in what type they end up as (bool for a toggle Button's
    // value(), double for a Valuator's) -- kept as the raw .fl text and
    // emitted verbatim as a D literal, letting the D compiler's own
    // implicit-conversion rules (confirmed: an int literal converts to
    // bool at a bool-typed parameter, e.g. `.compact(1)`) sort out the
    // right type at each call site, rather than this generator trying
    // to know every widget class's own value type.
    string valueRaw;
    bool hasValue;
    string compactRaw;
    bool hasCompact;
    string minimumRaw;
    bool hasMinimum;
    string maximumRaw;
    bool hasMaximum;
    string stepRaw;
    bool hasStep;
    string sliderSizeRaw;
    bool hasSliderSize;

    // A raw int/hex literal (e.g. "0xff50"), passed through verbatim to
    // `.shortcut()` -- already valid D syntax as-is, same reasoning as
    // `stepRaw`/`minimumRaw` above, no translation table needed.
    string shortcutRaw;
    bool hasShortcut;

    // "class Foo" -- names a pre-existing, separately-defined D subclass
    // to instantiate instead of this node's own plain type keyword's
    // default class (e.g. `new CubeView(...)` instead of `new Box(...)`
    // for `Fl_Box cube { ... class CubeView }`). See code_writer.d's
    // className().
    string classOverride;
    bool hasClassOverride;

    // Runs once this widget is constructed and its attributes are set,
    // but before any of its children are constructed (matching FLTK
    // Fluid's own "setup" semantics -- see `FLUID_DIALECT.md`'s "Known
    // dialect gaps" section for why there's no post-children
    // counterpart yet). Replaces the
    // four separately-numbered `code0`-`code3` FLTK slots: since
    // fldtk has no header/`.cxx` split, the other two FLTK slots
    // those numbers also covered (`#include`/`declare`, both purely
    // about *which file* to write to) don't apply here at all, and
    // nothing in this project has ever needed the fourth ("final",
    // post-children) slot FLTK also offers -- add it back as a
    // real, separate field the day something actually needs it, not
    // speculatively. A widget with more than one `setup` property in
    // its `.fl` source has each one appended in encounter order (see
    // `readProperty()` below), matching the concatenated-in-numeric-
    // order behavior `code0`-`code3` already had.
    string setupCode;
    bool hasSetupCode;

    string tooltip;
    bool hidden;
    bool deactivated;
    bool resizableFlag;

    /// FLTK: `Widget_Node::hotspot_` -- see `readProperty()`'s own
    /// `"hotspot"`/`"divider"` case for the dual-meaning shared storage.
    bool hotspotFlag;

    /// Not FLTK -- see `fluid.font_menu`'s own module doc comment
    /// for the full mechanism this opts a `Choice`/`Menu_`-owning node
    /// into (a shared, single-source-of-truth font list, instead of
    /// literal `MenuItem {}` children duplicated at every font-picking
    /// `Choice`).
    bool usesFontMenu;

    /// Same mechanism as `usesFontMenu` just above, for the 14-entry
    /// quick-pick color list instead -- see `fluid.color_menu`'s own
    /// module doc comment.
    bool usesColorMenu;

    // "image"/"deimage" -- a file path (resolved relative to the `.fl`
    // file's own directory, same convention as `DataNode.filename`),
    // ported from FLTK's `Widget_Image` (see `code_writer.d`'s own
    // `writeWidgetImage()` doc comment for the full scope). `compress_
    // image`/`compress_deimage` (FLTK's `Widget_Image::compress`,
    // default on) are real: when set, the generated code embeds the file's
    // own original bytes and decodes them once at runtime via the
    // matching codec's byte-buffer constructor; when cleared, it
    // embeds the format's *native in-memory* representation instead
    // (decoded RGB pixels for a plain raster format, or the XPM/XBM
    // codecs' own already-decoded string-row/bit-array form for
    // those two, matching FLTK's own "Pixmap and Bitmap images
    // always use their native in-memory representation" rule -- see
    // `code_writer.d`'s `writeOneImage()` for the full dispatch).
    // `bind_image`/`bind_deimage` and `scale_image`/`scale_deimage` are
    // real -- `bind` maps directly onto
    // `fl.widget.Widget.bindImage()`/`.bindDeimage()`, already-real,
    // already-ported ownership-taking methods (the widget releases the
    // image itself once no longer needed) distinct from plain
    // `image()`/`deimage()`, no core-library work needed. `scaleImageW`/
    // `.scaleImageH` (0/0 = natural size, matching FLTK's own
    // `scale_w`/`scale_h` default) map onto `fl.image.Image.scale()`,
    // called via `code_writer.d`'s `writeOneImage()` right after the
    // image/deimage assignment for generated D code, and via
    // `instantiate.d`'s own `applyProperties()` for the live canvas --
    // both the codegen and live-canvas paths need this, so a `.fl`
    // file with a real `scale_image` set, e.g.
    // `settings_panel.fl`'s own tab icons, shows the image at the
    // correctly scaled size both in generated code and while editing.
    string imageFilename;
    bool hasImage;
    bool compressImage = true;
    bool bindImage;
    int scaleImageW;
    int scaleImageH;
    string deimageFilename;
    bool hasDeimage;
    bool compressDeimage = true;
    bool bindDeimage;
    int scaleDeimageW;
    int scaleDeimageH;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "xywh":
        {
            auto parts = split(r.readValue());
            if (parts.length >= 4)
            {
                try
                {
                    x = to!int(parts[0]);
                    y = to!int(parts[1]);
                    w = to!int(parts[2]);
                    h = to!int(parts[3]);
                    hasXywh = true;
                }
                catch (ConvException)
                {
                    // Malformed project file -- leave hasXywh false
                    // rather than crash on a corrupt/hand-edited field.
                }
            }
            return true;
        }
        case "box":
            boxtype = r.readValue();
            hasBoxtype = true;
            return true;
        case "down_box":
            downBoxtype = r.readValue();
            hasDownBoxtype = true;
            return true;
        case "color":
            color = parseFlColor(r.readValue());
            return true;
        case "selection_color":
            selectionColor = parseFlColor(r.readValue());
            return true;
        case "labelfont":
            labelfont = readIntValue(r);
            return true;
        case "labelsize":
            labelsize = readIntValue(r);
            return true;
        case "textsize":
            textsize = readIntValue(r);
            return true;
        case "textfont":
            textfont = readIntValue(r);
            return true;
        case "textcolor":
            textcolorRaw = parseFlColor(r.readValue());
            return true;
        case "v_label_margin":
            vLabelMargin = readIntValue(r);
            return true;
        case "h_label_margin":
            // FLTK: `Widget_Node.cxx`'s own sibling of `v_label_margin`
            // just above, needed for the Style tab's "Label Margin:"
            // group's Horizontal field.
            hLabelMargin = readIntValue(r);
            return true;
        case "image_spacing":
            // FLTK: `Widget_Node.cxx`'s own `label_image_spacing()` --
            // same story as `h_label_margin` just above.
            imageSpacing = readIntValue(r);
            return true;
        case "labelcolor":
            labelcolorRaw = parseFlColor(r.readValue());
            return true;
        case "labeltype":
            labeltype = r.readValue();
            return true;
        case "value":
            valueRaw = r.readValue();
            hasValue = true;
            return true;
        case "compact":
            compactRaw = r.readValue();
            hasCompact = true;
            return true;
        case "minimum":
            minimumRaw = r.readValue();
            hasMinimum = true;
            return true;
        case "maximum":
            maximumRaw = r.readValue();
            hasMaximum = true;
            return true;
        case "step":
            stepRaw = r.readValue();
            hasStep = true;
            return true;
        case "slider_size":
            sliderSizeRaw = r.readValue();
            hasSliderSize = true;
            return true;
        case "shortcut":
            shortcutRaw = r.readValue();
            hasShortcut = true;
            return true;
        case "class":
            classOverride = r.readValue();
            hasClassOverride = true;
            return true;
        case "align":
            alignRaw = readIntValue(r);
            return true;
        case "when":
            whenRaw = readIntValue(r);
            return true;
        case "type":
            typeWord = r.readValue();
            return true;
        case "setup":
            // A second "setup" property on the same widget appends
            // rather than overwrites, matching FLTK's own
            // `extra_code_append()` -- lets a `.fl` author (or a
            // future project-writer round-trip) split setup code
            // across more than one property without losing any of it.
            setupCode ~= (hasSetupCode ? "\n" : "") ~ r.readValue();
            hasSetupCode = true;
            return true;
        case "tooltip":
            tooltip = r.readValue();
            return true;
        case "image":
            imageFilename = r.readValue();
            hasImage = true;
            return true;
        case "compress_image":
            compressImage = readIntValue(r) != 0;
            return true;
        case "bind_image":
            bindImage = readIntValue(r) != 0;
            return true;
        case "scale_image":
        {
            auto parts = split(r.readValue());
            if (parts.length >= 2)
            {
                try
                {
                    scaleImageW = to!int(parts[0]);
                    scaleImageH = to!int(parts[1]);
                }
                catch (ConvException)
                {
                }
            }
            return true;
        }
        case "deimage":
            deimageFilename = r.readValue();
            hasDeimage = true;
            return true;
        case "compress_deimage":
            compressDeimage = readIntValue(r) != 0;
            return true;
        case "bind_deimage":
            bindDeimage = readIntValue(r) != 0;
            return true;
        case "scale_deimage":
        {
            auto parts = split(r.readValue());
            if (parts.length >= 2)
            {
                try
                {
                    scaleDeimageW = to!int(parts[0]);
                    scaleDeimageH = to!int(parts[1]);
                }
                catch (ConvException)
                {
                }
            }
            return true;
        }
        case "hide":
            hidden = true;
            return true;
        case "deactivate":
            deactivated = true;
            return true;
        case "resizable":
            resizableFlag = true;
            return true;
        case "visible":
            return true; // Fluid-editor-only, no D equivalent needed
        case "hotspot":
        case "divider":
            // FLTK: `Widget_Node::hotspot_` -- a bare flag shared by
            // two meanings depending on node kind (`Widget_Node.h`'s own
            // comment: "hotspot is reused by menu items to indicate a
            // divider"): "hotspot" for an ordinary widget/window
            // (position the window at this widget when shown), "divider"
            // for a `Menu_Item_Node` (draws a separator line after this
            // item) -- same underlying storage either way, so both
            // keywords map to the one field here. Without this case,
            // `hotspot` would fall through to the generic "unrecognized
            // property" path, which conservatively consumes one value
            // token defensively -- but a *bare* flag has no value token
            // to consume, so that defensive read would eat the *next*
            // property's own name instead, desyncing the whole rest of
            // that node's property list (the same failure class already
            // documented in `function_node.d`'s own "private" case and
            // `class_node.d`'s own ":" case).
            hotspotFlag = true;
            return true;
        case "private":
            access = Access.private_;
            return true;
        case "protected":
            access = Access.protected_;
            return true;
        case "uses_font_menu":
            usesFontMenu = true;
            return true;
        case "uses_color_menu":
            usesColorMenu = true;
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}

private int readIntValue(Reader r)
{
    auto v = r.readValue();
    if (v.length == 0) return 0;
    try
        return to!int(v);
    catch (ConvException)
        return 0;
}

private int parseFlColor(string v)
{
    try
    {
        if (v.length > 2 && v[0 .. 2] == "0x")
            return to!int(v[2 .. $], 16);
        return to!int(v);
    }
    catch (ConvException)
    {
        return 0;
    }
}
