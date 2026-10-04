/*
 * Ported from FL/Fl_PostScript.H + src/drivers/PostScript/
 * Fl_PostScript_Graphics_Driver.H + src/drivers/PostScript/
 * Fl_PostScript.cxx (FLTK 1.5.0, ~/Repositories/fltk).
 *
 * **Scope**: `Fl_PostScript_Graphics_Driver.H` declares two entirely
 * different classes behind `#if USE_PANGO` -- one that extends
 * `Fl_Cairo_Graphics_Driver` (the Pango/Cairo build), one that extends
 * `Fl_Graphics_Driver` directly (the plain X11/Wayland-without-Pango
 * build). This port has neither Pango nor Cairo (both `Deferred`, see
 * `CLAUDE.md`), so only the `#else` (`! USE_PANGO`) branch of both that
 * header and `Fl_PostScript.cxx` is relevant here -- every function in
 * this module is a port of that branch specifically, not the Cairo one.
 *
 * **Both `Fl_EPS_File_Surface` and `Fl_PostScript_File_Device` are
 * covered; `Fl_Printer` is not.** `Fl_EPS_File_Surface` extends
 * `Fl_Widget_Surface` directly and its own `start_eps()` needs no
 * page/margin negotiation -- same shape as `fl.svg_file_surface.
 * SvgFileSurface`. `Fl_PostScript_File_Device` (`PostscriptFileDevice`
 * below) extends `Fl_Paged_Device` (`fl.paged_device.PagedDevice`,
 * real) and reuses `PostscriptGraphicsDriver` directly, no second
 * driver needed -- both its own `begin_job()` overloads are real: the
 * interactive one opens a real `Fl_Native_File_Chooser`
 * (`fl.native_file_chooser.NativeFileChooser`, already real -- an
 * earlier version of this comment wrongly called it an unported
 * blocker), the `File`-based one writes straight to a caller-owned
 * `File`. `Fl_Printer` (`FL/Fl_Printer.H`) is the one with genuinely
 * new, unported scope: on Linux it drives its own separate
 * `print_panel` dialog (a Fluid-generated form, not `Fl_Native_File_
 * Chooser`) before falling back to `Fl_PostScript_File_Device`'s
 * chooser or piping finished output through `popen("lp ...")` -- see
 * `FL/Fl_Printer.H`'s `PORTING.md` row for the full call chain.
 *
 * **`PostscriptGraphicsDriver` implements exactly the primitive family
 * `fl.graphics_driver.GraphicsDriver` declares** (see that module's own
 * doc comment for the authoritative list: color/rect/rectf/line/xyline/
 * yxline/polygon(3 or 4 points)/lineStyle/pushClip/popClip/arc/pie/the
 * vertex-path `end*()` family/plain text) -- same scope `fl.svg_file_
 * surface.SvgGraphicsDriver` covers, but note the two drivers' `arc()`/
 * `pie()`/vertex-path bodies are ported independently from their own
 * FLTK sources (`Fl_PostScript_Graphics_Driver::arc()`/`pie()` use a
 * different translate/scale convention than `Fl_SVG_Graphics_Driver`'s
 * own `arc_pie()`) -- do not derive one from the other.
 *
 * **Simplification carried over from FLTK's own vertex-path
 * design, made larger here**: FLTK's `begin_line()`/`vertex()`/
 * `end_line()` etc. accumulate points in *user* space and wrap the
 * whole path in a `concat()`/`reconcat()` pair applying the current
 * transform matrix (`m`) at PostScript-interpreter level. This port's
 * `fl.draw` already resolves every vertex through `transformX()`/
 * `transformY()` before it ever reaches a `GraphicsDriver` dispatch
 * call (see `GraphicsDriver.endLine()`'s own doc comment: "the
 * accumulated, already-transformed vertex list") -- so there is no
 * matrix left to `concat()`/`reconcat()` here at all, and `endPoints()`/
 * `endLine()`/`endLoop()`/`endPolygon()`/`endComplexPolygon()` below
 * just emit a plain `moveto`/`lineto` sequence directly in the
 * already-final coordinates, dropping FLTK's `concat()`/
 * `reconcat()`/`what`/`gap_` state machine entirely (nothing left for
 * it to do).
 *
 * **Text**: real vectorized PostScript text for the Latin alphabet +
 * Latin Extended-A + the small "extra characters supported by standard
 * PostScript fonts" table FLTK's own `FL/Fl_PostScript.H` documents
 * (see `psCodeFor()`) -- ported faithfully, including the custom 2-byte
 * `Helvetica2B`-style Type 0 fonts `prologText2` below builds and the
 * `show_pos_width` operator that stretches glyph spacing to match the
 * width `fl.draw.width()` measured on screen. **Not ported**: the
 * bitmap-fallback path (`transformed_draw_extra()`, FLTK's own
 * answer for `FL_FREE_FONT`-and-above fonts or any codepoint outside
 * that table -- draws is a captured screen bitmap instead of vector
 * text). A `draw()` call that hits either case draws nothing at all
 * rather than mis-render, matching this port's own documented-gap
 * convention (see `fl.svg_file_surface`'s "not yet ported: embedded
 * images" for the precedent). Also not ported for the same reason:
 * `rtl_draw()`'s bitmap-only implementation (no vector RTL text
 * FLTK either) and `draw(int angle, ...)` (rotated text -- no
 * caller in this port's `GraphicsDriver` dispatch surface yet, see that
 * module's own doc comment).
 *
 * **Not ported at all (images)**: `draw_image()`/`draw_pixmap()`/
 * `draw_bitmap()`/`draw_rgb()` and the RLE+ASCII85 image-encoding
 * machinery (`prepare_rle85()`/`write_rle85()`/`close_rle85()`,
 * `prolog_2_pixmap`, `prolog_3`) they depend on -- same "images
 * deferred" scope cut `fl.svg_file_surface` already made. Plain
 * (non-RLE) ASCII85 encoding *is* ported (`Ascii85Encoder` below),
 * since real vectorized text needs it independently of images.
 */
module fl.postscript;

import std.stdio : File;
import std.utf : decode;
import fl.enumerations : Color, Font, freeFont, white, capSquare;
import fl.graphics_driver : GraphicsDriver, Point;
import fl.widget_surface : WidgetSurface;
import fl.paged_device : PagedDevice, PageFormat, PageLayout, pageFormats, a4, landscape, reversed, media;
import fl.image_surface : SurfaceDevice;
import fldraw = fl.draw;

/**
 * Base prolog, ported verbatim from `Fl_PostScript.cxx`'s file-scope
 * `prolog` string (the `L`/`R`/`CL`/`FR`/`GS`/`GR`/`SP`/`LW`/`CF`/`SF`/
 * `FS`/`GL`/`SRGB` path/color/font primitives, plus the `A85RLE`/`CI`/
 * `GI`/`MI` image filters and `show_pos_width` text-width-stretching
 * operator). The image-filter definitions (`CI`/`GI`/`MI`) are dead
 * code here (no `draw_image()` dispatch exists to call them), kept
 * verbatim anyway rather than trimmed -- inert static text, and keeping
 * it byte-for-byte matched to FLTK costs nothing.
 */
private immutable string psProlog =
    "/L { /y2 exch def\n" ~
    "/x2 exch def\n" ~
    "/y1 exch def\n" ~
    "/x1 exch def\n" ~
    "newpath   x1 y1 moveto x2 y2 lineto\n" ~
    "stroke}\n" ~
    "bind def\n" ~
    "/R { /dy exch def\n" ~
    "/dx exch def\n" ~
    "/y exch def\n" ~
    "/x exch def\n" ~
    "newpath\n" ~
    "x y moveto\n" ~
    "dx 0 rlineto\n" ~
    "0 dy rlineto\n" ~
    "dx neg 0 rlineto\n" ~
    "closepath stroke\n" ~
    "} bind def\n" ~
    "/CL {\n" ~
    "/dy exch def\n" ~
    "/dx exch def\n" ~
    "/y exch def\n" ~
    "/x exch def\n" ~
    "newpath\n" ~
    "x y moveto\n" ~
    "dx 0 rlineto\n" ~
    "0 dy rlineto\n" ~
    "dx neg 0 rlineto\n" ~
    "closepath\n" ~
    "clip\n" ~
    "} bind def\n" ~
    "/FR { /dy exch def\n" ~
    "/dx exch def\n" ~
    "/y exch def\n" ~
    "/x exch def\n" ~
    "currentlinewidth 0 setlinewidth newpath\n" ~
    "x y moveto\n" ~
    "dx 0 rlineto\n" ~
    "0 dy rlineto\n" ~
    "dx neg 0 rlineto\n" ~
    "closepath fill setlinewidth\n" ~
    "} bind def\n" ~
    "/GS { gsave } bind  def\n" ~
    "/GR { grestore } bind def\n" ~
    "/SP { showpage } bind def\n" ~
    "/LW { setlinewidth } bind def\n" ~
    "/CF /Courier def\n" ~
    "/SF { /CF exch def } bind def\n" ~
    "/fsize 12 def\n" ~
    "/FS { /fsize exch def fsize CF findfont exch scalefont setfont }def \n" ~
    "/GL { setgray } bind def\n" ~
    "/SRGB { setrgbcolor } bind def\n" ~
    "/A85RLE { /ASCII85Decode filter /RunLengthDecode filter } bind def\n" ~
    "/CI { GS /py exch def /px exch def /sy exch def /sx exch def\n" ~
    "translate \n" ~
    "sx sy scale px py 8 \n" ~
    "[ px 0 0 py neg 0 py ]\n" ~
    "currentfile A85RLE\n false 3" ~
    " colorimage GR\n" ~
    "} bind def\n" ~
    "/GI { GS /py exch def /px exch def /sy exch def /sx exch def \n" ~
    "translate \n" ~
    "sx sy scale px py 8 \n" ~
    "[ px 0 0 py neg 0 py ]\n" ~
    "currentfile A85RLE\n" ~
    "image GR\n" ~
    "} bind def\n" ~
    "/MI { GS /py exch def /px exch def /sy exch def /sx exch def \n" ~
    "translate \n" ~
    "sx sy scale px py true \n" ~
    "[ px 0 0 py neg 0 py ]\n" ~
    "currentfile A85RLE\n" ~
    "imagemask GR\n" ~
    "} bind def\n" ~
    "/BFP { newpath moveto }  def\n" ~
    "/BP { newpath } bind def \n" ~
    "/PL { lineto } bind def \n" ~
    "/PM { moveto } bind def \n" ~
    "/MT { moveto } bind def \n" ~
    "/LT { lineto } bind def \n" ~
    "/EFP { closepath fill } bind def\n" ~
    "/ELP { stroke } bind def\n" ~
    "/ECP { closepath stroke } bind def\n" ~
    "/LW { setlinewidth } bind def\n" ~
    "/TR { translate } bind def\n" ~
    "/CT { concat } bind def\n" ~
    "/RCT { matrix invertmatrix concat} bind def\n" ~
    "/SC { scale } bind def\n" ~
    "/show_pos_width {GS moveto dup dup stringwidth pop exch length 2 div dup 2 le {pop 9999} if " ~
    "1 sub exch 3 index exch sub exch " ~
    "div 0 2 index 1 -1 scale ashow pop pop GR} bind def\n";

/**
 * `prolog_2` ("prolog relevant only if lang_level > 1"), ported
 * verbatim from `Fl_PostScript.cxx`. Builds the custom 2-byte Type 0
 * fonts (`Helvetica2B` etc. -- `_fontNames`/`psFontNames` below select
 * among these) that let `PostscriptGraphicsDriver.draw()` emit real
 * vector text using `ISOLatin1Encoding` for codepoints <= 0x17F and a
 * hand-built `LatinExtA` encoding for the small set of extra characters
 * `psCodeFor()` recognizes. The `CII`/`GII` color/gray image
 * dictionaries in here are dead code for the same reason `CI`/`GI`/`MI`
 * are in `psProlog` -- kept verbatim rather than trimmed. `prolog_2_
 * pixmap` and `prolog_3` (FLTK's own lang_level==2-pixmap-only and
 * lang_level>2-only prologs, both image-only) are **not** ported --
 * this driver never raises `lang_level_` above FLTK's own default
 * of 2 and never emits a pixmap pattern, so neither is ever needed.
 */
private immutable string psProlog2 =
    "/CII {GS /inter exch def /py exch def /px exch def /sy exch def /sx exch def \n" ~
    "translate \n" ~
    "sx sy scale\n" ~
    "/DeviceRGB setcolorspace\n" ~
    "/IDD 8 dict def\n" ~
    "IDD begin\n" ~
    "/ImageType 1 def\n" ~
    "/Width px def\n" ~
    "/Height py def\n" ~
    "/BitsPerComponent 8 def\n" ~
    "/Interpolate inter def\n" ~
    "/DataSource currentfile A85RLE def\n" ~
    "/MultipleDataSources false def\n" ~
    "/ImageMatrix [ px 0 0 py neg 0 py ] def\n" ~
    "/Decode [ 0 1 0 1 0 1 ] def\n" ~
    "end\n" ~
    "IDD image GR} bind def\n" ~
    "/GII {GS /inter exch def /py exch def /px exch def /sy exch def /sx exch def \n" ~
    "translate \n" ~
    "sx sy scale\n" ~
    "/DeviceGray setcolorspace\n" ~
    "/IDD 8 dict def\n" ~
    "IDD begin\n" ~
    "/ImageType 1 def\n" ~
    "/Width px def\n" ~
    "/Height py def\n" ~
    "/BitsPerComponent 8 def\n" ~
    "/Interpolate inter def\n" ~
    "/DataSource currentfile A85RLE def\n" ~
    "/MultipleDataSources false def\n" ~
    "/ImageMatrix [ px 0 0 py neg 0 py ] def\n" ~
    "/Decode [ 0 1 ] def\n" ~
    "end\n" ~
    "IDD image GR} bind def\n" ~
    "/ToISO { dup findfont dup length dict copy begin /Encoding ISOLatin1Encoding def currentdict end definefont pop } def\n" ~
    "/Helvetica ToISO /Helvetica-Bold ToISO /Helvetica-Oblique ToISO /Helvetica-BoldOblique ToISO \n" ~
    "/Courier ToISO /Courier-Bold ToISO /Courier-Oblique ToISO /Courier-BoldOblique ToISO \n" ~
    "/Times-Roman ToISO /Times-Bold ToISO /Times-Italic ToISO /Times-BoldItalic ToISO \n" ~
    "/LatinExtA \n" ~
    "[ " ~
    " /Amacron /amacron /Abreve /abreve /Aogonek /aogonek\n" ~
    " /Cacute  /cacute  /Ccircumflex  /ccircumflex  /Cdotaccent  /cdotaccent  /Ccaron  /ccaron \n" ~
    " /Dcaron  /dcaron   /Dcroat  /dcroat\n" ~
    " /Emacron  /emacron  /Ebreve  /ebreve  /Edotaccent  /edotaccent  /Eogonek  /eogonek  /Ecaron  /ecaron\n" ~
    " /Gcircumflex  /gcircumflex  /Gbreve  /gbreve  /Gdotaccent  /gdotaccent  /Gcommaaccent  /gcommaaccent \n" ~
    " /Hcircumflex /hcircumflex  /Hbar  /hbar  \n" ~
    " /Itilde  /itilde  /Imacron  /imacron  /Ibreve  /ibreve  /Iogonek  /iogonek /Idotaccent  /dotlessi  \n" ~
    " /IJ  /ij  /Jcircumflex  /jcircumflex\n" ~
    " /Kcommaaccent  /kcommaaccent  /kgreenlandic  \n" ~
    " /Lacute  /lacute  /Lcommaaccent  /lcommaaccent   /Lcaron  /lcaron  /Ldotaccent /ldotaccent   /Lslash  /lslash \n" ~
    " /Nacute  /nacute  /Ncommaaccent  /ncommaaccent  /Ncaron  /ncaron  /napostrophe  /Eng  /eng  \n" ~
    " /Omacron  /omacron /Obreve  /obreve  /Ohungarumlaut  /ohungarumlaut  /OE  /oe \n" ~
    " /Racute  /racute  /Rcommaaccent  /rcommaaccent  /Rcaron  /rcaron \n" ~
    " /Sacute /sacute  /Scircumflex  /scircumflex  /Scedilla /scedilla /Scaron  /scaron \n" ~
    " /Tcommaaccent  /tcommaaccent  /Tcaron  /tcaron  /Tbar  /tbar \n" ~
    " /Utilde  /utilde /Umacron /umacron  /Ubreve  /ubreve  /Uring  /uring  /Uhungarumlaut  /uhungarumlaut  /Uogonek /uogonek \n" ~
    " /Wcircumflex  /wcircumflex  /Ycircumflex  /ycircumflex  /Ydieresis \n" ~
    " /Zacute /zacute /Zdotaccent /zdotaccent /Zcaron /zcaron \n" ~
    " /longs \n" ~
    " /florin  /circumflex  /caron  /breve  /dotaccent  /ring \n" ~
    " /ogonek  /tilde  /hungarumlaut  /endash /emdash \n" ~
    " /quoteleft  /quoteright  /quotesinglbase  /quotedblleft  /quotedblright \n" ~
    " /quotedblbase  /dagger  /daggerdbl  /bullet  /ellipsis \n" ~
    " /perthousand  /guilsinglleft  /guilsinglright  /fraction  /Euro \n" ~
    " /trademark /partialdiff  /Delta /summation  /radical \n" ~
    " /infinity /notequal /lessequal /greaterequal /lozenge \n" ~
    " /fi /fl /apple \n" ~
    " ] def \n" ~
    " /mycharstrings /Helvetica findfont /CharStrings get def\n" ~
    " /PSname2 { dup mycharstrings exch known {LatinExtA 3 -1 roll 3 -1 roll put}{pop pop} ifelse } def \n" ~
    " 16#20 /Gdot PSname2 16#21 /gdot PSname2 16#30 /Idot PSname2 16#3F /Ldot PSname2 16#40 /ldot PSname2 16#7F /slong PSname2 \n" ~
    "/ToLatinExtA { findfont dup length dict copy begin /Encoding LatinExtA def currentdict end definefont pop } def\n" ~
    "/HelveticaExt /Helvetica ToLatinExtA \n" ~
    "/Helvetica-BoldExt /Helvetica-Bold ToLatinExtA /Helvetica-ObliqueExt /Helvetica-Oblique ToLatinExtA  \n" ~
    "/Helvetica-BoldObliqueExt /Helvetica-BoldOblique ToLatinExtA  \n" ~
    "/CourierExt /Courier ToLatinExtA /Courier-BoldExt /Courier-Bold ToLatinExtA  \n" ~
    "/Courier-ObliqueExt /Courier-Oblique ToLatinExtA /Courier-BoldObliqueExt /Courier-BoldOblique ToLatinExtA \n" ~
    "/Times-RomanExt /Times-Roman ToLatinExtA /Times-BoldExt /Times-Bold ToLatinExtA  \n" ~
    "/Times-ItalicExt /Times-Italic ToLatinExtA /Times-BoldItalicExt /Times-BoldItalic ToLatinExtA \n" ~
    "/To2byte { 6 dict begin /FontType 0 def \n" ~
    "/FDepVector 3 1 roll findfont exch findfont 2 array astore def \n" ~
    "/FontMatrix [1  0  0  1  0  0] def /FMapType 6 def /Encoding [ 0 1 0 ] def\n" ~
    "/SubsVector < 01 0100 00A7 > def\n" ~
    "currentdict end definefont pop } def\n" ~
    "/Helvetica2B /HelveticaExt /Helvetica To2byte \n" ~
    "/Helvetica-Bold2B /Helvetica-BoldExt /Helvetica-Bold To2byte \n" ~
    "/Helvetica-Oblique2B /Helvetica-ObliqueExt /Helvetica-Oblique To2byte \n" ~
    "/Helvetica-BoldOblique2B /Helvetica-BoldObliqueExt /Helvetica-BoldOblique To2byte \n" ~
    "/Courier2B /CourierExt /Courier To2byte \n" ~
    "/Courier-Bold2B /Courier-BoldExt /Courier-Bold To2byte \n" ~
    "/Courier-Oblique2B /Courier-ObliqueExt /Courier-Oblique To2byte \n" ~
    "/Courier-BoldOblique2B /Courier-BoldObliqueExt /Courier-BoldOblique To2byte \n" ~
    "/Times-Roman2B /Times-RomanExt /Times-Roman To2byte \n" ~
    "/Times-Bold2B /Times-BoldExt /Times-Bold To2byte \n" ~
    "/Times-Italic2B /Times-ItalicExt /Times-Italic To2byte \n" ~
    "/Times-BoldItalic2B /Times-BoldItalicExt /Times-BoldItalic To2byte \n";

/// Ported from `_fontNames[]` (`Fl_PostScript.cxx`), indexed directly
/// by `Fl_Font`/`fl.enumerations.Font` (0..15) -- the 2-byte Type 0
/// font each standard FLTK font selects via `psProlog2`'s `To2byte`.
/// Note index 12 (`symbol`)/15 (`zapfDingbats`) use the *plain*
/// PostScript `Symbol`/`ZapfDingbats` fonts directly (no `2B`/ISO-
/// encoding wrapper -- matching FLTK exactly, presumably because
/// neither font's own built-in encoding maps usefully onto Latin
/// text), and index 13/14 (`screen`/`screenBold`) fall back to plain
/// `Courier2B`/`Courier-Bold2B` (FLTK has no fixed-width "screen"
/// PostScript font either).
private static immutable string[16] psFontNames = [
    "Helvetica2B", "Helvetica-Bold2B", "Helvetica-Oblique2B", "Helvetica-BoldOblique2B",
    "Courier2B", "Courier-Bold2B", "Courier-Oblique2B", "Courier-BoldOblique2B",
    "Times-Roman2B", "Times-Bold2B", "Times-Italic2B", "Times-BoldItalic2B",
    "Symbol", "Courier2B", "Courier-Bold2B", "ZapfDingbats",
];

/// Ported from `extra_table_roman[]` (`Fl_PostScript.cxx`'s file-scope
/// `is_in_table()`) -- unicode codepoints of the extra characters
/// standard PostScript fonts support beyond Latin Extended-A (see
/// `FL/Fl_PostScript.H`'s own doc comment table). `psCodeFor()` maps a
/// hit at index `i` to PostScript code `0x180 + i`, matching
/// `psProlog2`'s `LatinExtA` encoding array position-for-position (the
/// `16#7F /slong PSname2` line caps `LatinExtA` at exactly this many
/// extra slots after the Latin-Extended-A block).
private static immutable uint[39] psExtraTableRoman = [
    0x192, 0x2C6, 0x2C7,
    0x2D8, 0x2D9, 0x2DA, 0x2DB, 0x2DC, 0x2DD,
    0x2013, 0x2014, 0x2018, 0x2019,
    0x201A, 0x201C, 0x201D, 0x201E,
    0x2020, 0x2021, 0x2022,
    0x2026, 0x2030, 0x2039, 0x203A,
    0x2044, 0x20AC, 0x2122,
    0x2202, 0x2206, 0x2211, 0x221A,
    0x221E, 0x2260, 0x2264,
    0x2265,
    0x25CA, 0xFB01, 0xFB02,
    0xF8FF,
];

/// Ported from `is_in_table()` -- maps a unicode codepoint to its
/// PostScript encoding position in this driver's custom 2-byte fonts,
/// `false` if the codepoint isn't handled (`draw()` then draws nothing
/// rather than FLTK's own bitmap fallback, see this module's own
/// top comment).
private bool psCodeFor(uint utf, out uint code)
{
    if (utf <= 0x17F)
    {
        code = utf;
        return true;
    }
    foreach (i, v; psExtraTableRoman)
    {
        if (v == utf)
        {
            code = cast(uint)(i + 0x180);
            return true;
        }
    }
    return false;
}

/**
 * Plain (non-RLE) ASCII85 encoder, ported from `Fl_PostScript_Graphics_
 * Driver::prepare85()`/`write85()`/`close85()` (`Fl_PostScript_image.cxx`)
 * -- the RLE-wrapping half (`prepare_rle85()`/etc., used only for
 * bitmap images) isn't ported, see this module's own top comment.
 * Writes encoded output directly to `file` as bytes accumulate (no
 * caller needs the encoded bytes themselves, only the side effect of
 * having written them), matching FLTK's own "encode straight to
 * `output`" design.
 */
private struct Ascii85Encoder
{
    private File file_;
    private ubyte[4] bytes4_;
    private int l4_;
    private int blocks_;

    this(File f)
    {
        file_ = f;
    }

    // ASCII85-encodes 4 input bytes into up to 5 output characters.
    // Ported from the file-scope `convert85()`.
    private static int convert85(const ubyte[4] bytes4, ref ubyte[5] chars5)
    {
        if (bytes4[0] == 0 && bytes4[1] == 0 && bytes4[2] == 0 && bytes4[3] == 0)
        {
            chars5[0] = 'z';
            return 1;
        }
        uint val = bytes4[0] * (256u * 256 * 256) + bytes4[1] * (256u * 256) + bytes4[2] * 256 + bytes4[3];
        chars5[0] = cast(ubyte)(val / 52200625 + 33);
        val %= 52200625;
        chars5[1] = cast(ubyte)(val / 614125 + 33);
        val %= 614125;
        chars5[2] = cast(ubyte)(val / 7225 + 33);
        val %= 7225;
        chars5[3] = cast(ubyte)(val / 85 + 33);
        chars5[4] = cast(ubyte)(val % 85 + 33);
        return 5;
    }

    void write(const(ubyte)[] p)
    {
        size_t i = 0;
        while (i < p.length)
        {
            int c = 4 - l4_;
            if (cast(int)(p.length - i) < c) c = cast(int)(p.length - i);
            bytes4_[l4_ .. l4_ + c] = p[i .. i + c];
            i += c;
            l4_ += c;
            if (l4_ == 4)
            {
                ubyte[5] chars5;
                int n = convert85(bytes4_, chars5);
                file_.rawWrite(chars5[0 .. n]);
                l4_ = 0;
                blocks_++;
                if (blocks_ >= 16)
                {
                    file_.write("\n");
                    blocks_ = 0;
                }
            }
        }
    }

    // Ported from `close85()`.
    void close()
    {
        if (l4_)
        {
            int l = l4_;
            while (l < 4) bytes4_[l++] = 0;
            ubyte[5] chars5;
            int n = convert85(bytes4_, chars5);
            if (n == 1) chars5[] = '!';
            file_.rawWrite(chars5[0 .. l4_ + 1]);
        }
        file_.write("~>");
    }
}

/**
 * Implements the `/RunLengthEncode` + `/ASCII85Encode` PostScript
 * filter pair (`A85RLE` in `psProlog`) -- ported from
 * `prepare_rle85()`/`write_rle85()`/`close_rle85()`. A byte-at-a-time
 * run-length encoder (runs of 3-128 identical bytes collapse to a
 * 2-byte control sequence; non-run data accumulates in a 128-byte
 * buffer and gets flushed with its own length-prefix byte) sitting on
 * top of `Ascii85Encoder` above -- needed for `PostscriptGraphicsDriver
 * .drawImage()`/`drawBitmap()`'s image-data payloads, which the
 * `CII`/`GII`/`MI` PostScript operators (already transcribed verbatim
 * into `psProlog`/`psProlog2`, just unused until now) expect to read
 * via `currentfile A85RLE`.
 */
private struct Rle85Encoder
{
    private Ascii85Encoder data85_;
    private ubyte[128] buffer_;
    private int count_;
    private int runLength_;

    this(File f)
    {
        data85_ = Ascii85Encoder(f);
    }

    // Ported from `write_rle85()`.
    void write(ubyte b)
    {
        if (runLength_ > 0)
        {
            if (b == buffer_[0] && runLength_ < 128)
            {
                runLength_++;
                return;
            }
            else
            {
                ubyte c = cast(ubyte)(257 - runLength_);
                data85_.write((&c)[0 .. 1]);
                data85_.write(buffer_[0 .. 1]);
                runLength_ = 0;
            }
        }
        if (count_ >= 2 && b == buffer_[count_ - 1] && b == buffer_[count_ - 2])
        {
            if (count_ > 2)
            {
                ubyte c = cast(ubyte)(count_ - 2 - 1);
                data85_.write((&c)[0 .. 1]);
                data85_.write(buffer_[0 .. count_ - 2]);
            }
            runLength_ = 3;
            buffer_[0] = b;
            count_ = 0;
            return;
        }
        if (count_ >= 128)
        {
            ubyte c = cast(ubyte)(count_ - 1);
            data85_.write((&c)[0 .. 1]);
            data85_.write(buffer_[0 .. count_]);
            count_ = 0;
        }
        buffer_[count_++] = b;
    }

    // Ported from `close_rle85()`.
    void close()
    {
        if (runLength_ > 0)
        {
            ubyte c = cast(ubyte)(257 - runLength_);
            data85_.write((&c)[0 .. 1]);
            data85_.write(buffer_[0 .. 1]);
        }
        else if (count_)
        {
            ubyte c = cast(ubyte)(count_ - 1);
            data85_.write((&c)[0 .. 1]);
            data85_.write(buffer_[0 .. count_]);
        }
        ubyte eod = 128;
        data85_.write((&eod)[0 .. 1]);
        data85_.close();
    }
}

unittest
{
    // Rle85Encoder -- headless, no PostScript file-surface machinery
    // needed, just the encoder writing to a temp file directly.
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : endsWith;

    auto path = buildPath(tempDir(), "fldtk-rle85-test-" ~ randomUUID().toString() ~ ".bin");
    scope (exit) if (exists(path)) remove(path);

    // A long run of one repeated byte should compress far smaller than
    // the same number of arbitrary distinct bytes -- confirms the
    // run-length branch actually engages instead of just falling
    // through to plain ASCII85 (which alone would produce roughly the
    // same output size either way).
    {
        auto f = File(path, "wb"); // binary: see EpsFileSurface's own doc comment on why
        auto rle = Rle85Encoder(f);
        foreach (i; 0 .. 200) rle.write(42);
        rle.close();
    }
    auto runOutput = readText(path);
    assert(runOutput.endsWith("~>")); // Ascii85Encoder's own EOD marker

    auto path2 = buildPath(tempDir(), "fldtk-rle85-test2-" ~ randomUUID().toString() ~ ".bin");
    scope (exit) if (exists(path2)) remove(path2);
    {
        auto f = File(path2, "wb");
        auto rle = Rle85Encoder(f);
        foreach (i; 0 .. 200) rle.write(cast(ubyte)(i * 37 + 11)); // no repeats of 3+
        rle.close();
    }
    auto distinctOutput = readText(path2);
    assert(distinctOutput.endsWith("~>"));
    assert(runOutput.length < distinctOutput.length);
}

/**
 * Ported (the slice `fl.graphics_driver.GraphicsDriver` covers -- see
 * this module's own top comment) from `Fl_PostScript_Graphics_Driver`
 * (the `! USE_PANGO` branch). Each override emits PostScript operators
 * using the small macro set `psProlog` defines (`MT`/`LT`/`ECP`/`EFP`/
 * `ELP` for path building, `GS`/`GR` for save/restore, `CS`/`CR` for
 * clip save/restore, `GL`/`SRGB` for color).
 */
class PostscriptGraphicsDriver : GraphicsDriver
{
    private File output_;
    private ubyte cr_, cg_, cb_;

    /// The most recently applied line style, remembered so `recover()`
    /// (called after every `CR`/`CS` clip save/restore, which discards
    /// the interpreter's current line-width/cap/join/dash state along
    /// with the clip path -- see `pushClip()`/`popClip()`) can just
    /// call `lineStyle()` again instead of duplicating its logic.
    /// Ported from `Fl_PostScript_Graphics_Driver::linestyle_`/
    /// `linewidth_`/`linedash_`.
    private int lastStyle_;
    private int lastWidth_; /// ditto
    private const(ubyte)[] lastDashes_; /// ditto

    /// This driver's own clip-rectangle stack. Ported from
    /// `Fl_PostScript_Graphics_Driver::Clip`/`clip_` -- needed (unlike
    /// `fl.svg_file_surface.SvgGraphicsDriver`'s clipping, which needs
    /// no stack of its own) because a PostScript `CR` (clip restore)
    /// discards the *entire* current clip path, so `popClip()` must
    /// re-assert the enclosing rectangle by hand rather than relying on
    /// nested-scope structure the way an SVG `<g clip-path>` can.
    private struct ClipRect { int x, y, w, h; }
    private ClipRect[] clipStack_;

    /// The page's background color, `drawImage()`/`drawBitmap()`'s
    /// alpha-compositing target for `d>3`/mono+alpha image data (this
    /// driver's `lang_level_` is always 2, see `startEps()`'s own doc
    /// comment, so real PostScript-level transparency masking is out of
    /// scope -- see `drawImage()`'s own doc comment for why). Ported
    /// from `Fl_PostScript_Graphics_Driver::bg_r`/`bg_g`/`bg_b`, default
    /// white matching FLTK's own constructor (`bg_r = bg_g = bg_b =
    /// 255;`).
    private ubyte bgR_ = 255, bgG_ = 255, bgB_ = 255;

    /// Whether an interpolation hint is requested for images (the
    /// `interp`/`inter` boolean parameter `CII`/`GII`/`MI` all take).
    /// Ported from `Fl_PostScript_Graphics_Driver::interpolate_` --
    /// FLTK has no public setter for this either (its own
    /// `interpolate()` get/set pair is commented out in the header),
    /// so this stays permanently at its default (`false`, matching
    /// FLTK's implicit zero-init).
    private bool interpolate_ = false;

    /// Page size in points, set by `startEps()`. Ported from `pw_`/
    /// `ph_`.
    double pw_ = 0, ph_ = 0;

    /// Ported from `left_margin`/`top_margin`/`scale_x`/`scale_y`/
    /// `angle` -- ~zero-initialized here rather than left
    /// uninitialized. FLTK's own `Fl_EPS_File_Surface`-only usage
    /// (via `start_eps()`) never initializes these at all before
    /// `Fl_EPS_File_Surface::origin()` can read them through
    /// `ps_origin()`; only `Fl_PostScript_File_Device::start_postscript()`
    /// (a different, unported call path -- see this module's own top
    /// comment) sets `left_margin`/`top_margin` for real. Filed as an
    /// `FLTK_ISSUES.md` candidate rather than ported as an
    /// uninitialized read.
    int leftMargin_ = 0, topMargin_ = 0;
    double scaleX_ = 1, scaleY_ = 1; /// ditto
    double angle_ = 0; /// ditto

    this(File f)
    {
        output_ = f;
    }

    /// The underlying file. Ported from
    /// `Fl_PostScript_Graphics_Driver::file()`.
    File file() { return output_; }

    private void emitColor()
    {
        if (cr_ == cg_ && cg_ == cb_)
            output_.writef("%g GL\n", cr_ / 255.0);
        else
            output_.writef("%g %g %g SRGB\n", cr_ / 255.0, cg_ / 255.0, cb_ / 255.0);
    }

    override void color(Color c)
    {
        fldraw.colorToRgb8(c, cr_, cg_, cb_);
        emitColor();
    }

    override void rectf(int x, int y, int w, int h)
    {
        output_.writef("%g %g %d %d FR\n", x - 0.5, y - 0.5, w, h);
    }

    override void rect(int x, int y, int w, int h)
    {
        output_.write("GS\nBP\n");
        output_.writef("%d %d MT\n", x, y);
        output_.writef("%d %d LT\n", x + w - 1, y);
        output_.writef("%d %d LT\n", x + w - 1, y + h - 1);
        output_.writef("%d %d LT\n", x, y + h - 1);
        output_.write("ECP\nGR\n");
    }

    override void line(int x, int y, int x1, int y1)
    {
        output_.write("GS\n");
        output_.writef("%d %d %d %d L\n", x, y, x1, y1);
        output_.write("GR\n");
    }

    override void xyline(int x, int y, int x1)
    {
        output_.write("GS\nBP\n");
        output_.writef("%d %d MT\n", x, y);
        output_.writef("%d %d LT\n", x1, y);
        output_.write("ELP\nGR\n");
    }

    override void yxline(int x, int y, int y1)
    {
        output_.write("GS\nBP\n");
        output_.writef("%d %d MT\n", x, y);
        output_.writef("%d %d LT\n", x, y1);
        output_.write("ELP\nGR\n");
    }

    override void polygon(int x, int y, int x1, int y1, int x2, int y2)
    {
        output_.write("GS\nBP\n");
        output_.writef("%d %d MT\n", x, y);
        output_.writef("%d %d LT\n", x1, y1);
        output_.writef("%d %d LT\n", x2, y2);
        output_.write("EFP\nGR\n");
    }

    override void polygon(int x, int y, int x1, int y1, int x2, int y2, int x3, int y3)
    {
        output_.write("GS\nBP\n");
        output_.writef("%d %d MT\n", x, y);
        output_.writef("%d %d LT\n", x1, y1);
        output_.writef("%d %d LT\n", x2, y2);
        output_.writef("%d %d LT\n", x3, y3);
        output_.write("EFP\nGR\n");
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::line_style()`. The
    /// `(style>>8)&3`/`(style>>12)&3` cap/join extraction and the
    /// `fl.draw.dashPatternFor()` reuse for the auto-dash-from-style-
    /// bits case are the same bit-layout adaptation `fl.svg_file_
    /// surface.SvgGraphicsDriver.lineStyle()` already established
    /// (this port's own simpler `lineStyle()` bit layout, not
    /// FLTK's `FL_CAP_*`/`FL_JOIN_*` masks) -- ported independently
    /// here since PostScript's `setlinecap`/`setlinejoin` take
    /// different integer codes (0/1/2) than SVG's cap/join name
    /// strings.
    override void lineStyle(int style, int width, const(ubyte)[] dashes)
    {
        lastStyle_ = style;
        lastWidth_ = width;
        lastDashes_ = dashes;

        bool width0 = width == 0;
        int w = width0 ? 1 : width;
        output_.writef("%d setlinewidth\n", w);

        // Ported from line_style()'s "for screen drawing compatibility"
        // system-line special case: an unstyled, undashed, zero-width
        // line gets a square cap rather than the default butt cap.
        int effStyle = style;
        if (!style && dashes.length == 0 && width0)
            effStyle = capSquare;

        static immutable int[4] capValues = [0, 0, 1, 2];
        static immutable int[4] joinValues = [0, 0, 1, 2];
        output_.writef("%d setlinecap\n", capValues[(effStyle >> 8) & 3]);
        output_.writef("%d setlinejoin\n", joinValues[(effStyle >> 12) & 3]);

        const(ubyte)[] d = dashes;
        if (d.length == 0 && (effStyle & 0xff) != 0)
            d = fldraw.dashPatternFor(effStyle, w);

        output_.write("[");
        foreach (v; d) output_.writef("%d ", v);
        output_.write("] 0 setdash\n");
    }

    override void pushClip(int x, int y, int w, int h)
    {
        clipStack_ ~= ClipRect(x, y, w, h);
        output_.write("CR\nCS\n");
        recover();
        output_.writef("%g %g %d %d CL\n", x - 0.5, y - 0.5, w, h);
    }

    override void popClip()
    {
        if (clipStack_.length) clipStack_ = clipStack_[0 .. $ - 1];
        output_.write("CR\nCS\n");
        if (clipStack_.length)
        {
            auto c = clipStack_[$ - 1];
            output_.writef("%g %g %d %d CL\n", c.x - 0.5, c.y - 0.5, c.w, c.h);
        }
        recover();
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::recover()`, minus
    /// the `font()` call: unlike FLTK (which caches the current
    /// font as `Fl_Font_Descriptor` state on the driver), `draw()`
    /// below re-selects the PostScript font on every call from
    /// `fl.draw.fl_font()`/`fl_size()` directly (see `draw()`'s own doc
    /// comment), so there is no persistent font state here to restore.
    private void recover()
    {
        emitColor();
        lineStyle(lastStyle_, lastWidth_, lastDashes_);
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::arc(int,...)`.
    /// Unlike `fl.svg_file_surface.SvgGraphicsDriver.arcPie()`, this is
    /// ported from PostScript's own `arc(int,...)`/`pie(int,...)`
    /// bodies directly, not derived from the SVG driver's -- the two
    /// use different translate/scale conventions. Draws into a local
    /// unit-circle space via `TR`/`SC` (undone again before the
    /// stroke), matching FLTK's own `begin_line()`/`end_line()`
    /// wrapping minus the now-unnecessary `concat()`/`reconcat()` CTM
    /// bookkeeping (see this module's own top comment).
    override void arc(int x, int y, int w, int h, double a1, double a2)
    {
        if (w <= 1 || h <= 1) return;
        double cx = x + w / 2.0 - 0.5, cy = y + h / 2.0 - 0.5;
        double sx = (w - 1) / 2.0, sy = (h - 1) / 2.0;
        output_.write("GS\nGS\nBP\n");
        output_.writef("%g %g TR\n", cx, cy);
        output_.writef("%g %g SC\n", sx, sy);
        arcOp(0, 0, 1, a2, a1);
        output_.writef("%g %g SC\n", sx != 0 ? 2.0 / (w - 1) : 1.0, sy != 0 ? 2.0 / (h - 1) : 1.0);
        output_.writef("%g %g TR\n", -cx, -cy);
        output_.write("ELP\nGR\nGR\n");
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::pie(int,...)`. The
    /// initial `0 0 MT` plus the PostScript `arc`/`arcn` operator's own
    /// "connect from the current point" behavior is what turns the arc
    /// into a closed pie wedge once `EFP` (`closepath fill`) runs --
    /// same mechanism as FLTK, no separate "close back to center"
    /// step needed.
    override void pie(int x, int y, int w, int h, double a1, double a2)
    {
        double cx = x + w / 2.0 - 0.5, cy = y + h / 2.0 - 0.5;
        double sx = (w - 1) / 2.0, sy = (h - 1) / 2.0;
        output_.write("GS\nGS\nBP\n");
        output_.writef("%g %g TR\n", cx, cy);
        output_.writef("%g %g SC\n", sx, sy);
        output_.write("0 0 MT\n");
        arcOp(0, 0, 1, a2, a1);
        output_.write("EFP\nGR\nGR\n");
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::arc(double x, double
    /// y, double r, double start, double a)` -- the raw `arc`/`arcn`
    /// emitter `arc(int,...)`/`pie(int,...)` above both delegate to
    /// after setting up their own local unit-circle transform. Named
    /// `arcOp` here (not overloaded as `arc()`) since D, unlike C++,
    /// can't distinguish this from the `int`-typed override above by
    /// argument type alone in every calling context this module needs.
    private void arcOp(double x, double y, double r, double start, double a)
    {
        if (start > a)
            output_.writef("%g %g %g %g %g arc\n", x, y, r, -start, -a);
        else
            output_.writef("%g %g %g %g %g arcn\n", x, y, r, -start, -a);
    }

    private void emitPath(const(Point)[] pts, string closeOp)
    {
        if (pts.length == 0) return;
        output_.write("GS\nBP\n");
        output_.writef("%d %d MT\n", pts[0].x, pts[0].y);
        foreach (p; pts[1 .. $]) output_.writef("%d %d LT\n", p.x, p.y);
        output_.write(closeOp ~ "\nGR\n");
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::end_points()`/
    /// `vertex()`'s `what==POINTS` branch: every accumulated point
    /// becomes its own `moveto` with no connecting `lineto` (a stroke
    /// only marks something visible where the line cap itself draws a
    /// dot, e.g. `capRound`/`capSquare` -- matching FLTK exactly,
    /// including that a `capFlat` points path draws nothing).
    override void endPoints(const(Point)[] pts)
    {
        if (pts.length == 0) return;
        output_.write("GS\nBP\n");
        foreach (p; pts) output_.writef("%d %d MT\n", p.x, p.y);
        output_.write("ELP\nGR\n");
    }

    override void endLine(const(Point)[] pts)
    {
        emitPath(pts, "ELP");
    }

    override void endLoop(const(Point)[] pts)
    {
        emitPath(pts, "ECP");
    }

    override void endPolygon(const(Point)[] pts)
    {
        emitPath(pts, "EFP");
    }

    override void endComplexPolygon(const(Point)[] pts)
    {
        emitPath(pts, "EFP");
    }

    /// A PostScript page has no "screen" to be device-pixel-dense
    /// relative to -- `Fl_PostScript_Graphics_Driver` extends the plain
    /// `Fl_Graphics_Driver` FLTK (not `Fl_Scalable_Graphics_Driver`)
    /// and its own `transformed_vertex()` emits the raw matrix-
    /// transformed value with no `scale()` multiply. See
    /// `GraphicsDriver.wantsUnscaledVertices()`'s own doc comment.
    override bool wantsUnscaledVertices() const { return true; }

    /**
     * Ported from `Fl_PostScript_Graphics_Driver::transformed_draw()`
     * (real vector text) -- see this module's own top comment for what
     * `transformed_draw_extra()`'s bitmap fallback path this
     * deliberately drops. Always re-selects the PostScript font (`SF`/
     * `FS`) from `fl.draw.fl_font()`/`fl_size()` rather than caching
     * "did it change", same "just recompute every call" simplification
     * `fl.svg_file_surface.SvgGraphicsDriver.draw()` already uses.
     */
    override void draw(const(char)[] str, int nChars, int x, int y)
    {
        if (nChars <= 0 || nChars > str.length) return;
        auto slice = str[0 .. nChars];
        int w = cast(int) fldraw.width(slice);
        if (w == 0) return;

        auto face = fldraw.fl_font();
        if (face < 0 || face >= freeFont) return; // see this module's own top comment
        auto size = fldraw.fl_size();

        output_.writef("/%s SF\n", psFontNames[face]);
        output_.writef("%g FS\n", cast(double) size);

        output_.writef("%d <~", w);
        auto enc = Ascii85Encoder(output_);
        size_t i = 0;
        while (i < slice.length)
        {
            dchar ch = decode(slice, i);
            uint code;
            if (!psCodeFor(cast(uint) ch, code))
            {
                // Unhandled codepoint -- close and discard the opened
                // (and, so far, empty or partial) hex string rather
                // than emit invalid PostScript, matching FLTK's
                // own "close and ignore" comment at this exact point.
                output_.write("~> pop pop\n");
                return;
            }
            ubyte[2] c = [cast(ubyte)((code >> 8) & 0xff), cast(ubyte)(code & 0xff)];
            enc.write(c[]);
        }
        enc.close();
        output_.writef(" %g %g show_pos_width\n", cast(double) x, cast(double) y);
    }

    /**
     * Draws `str` at `(x,y)`, rotated `angle` degrees counterclockwise.
     * Ported from `Fl_PostScript_Graphics_Driver::draw(int, const char*,
     * int, int, int)` (`src/drivers/PostScript/Fl_PostScript.cxx`) --
     * `GS`/`GR` bracket a PostScript `gsave`/`grestore` (this module's
     * own established shorthand, see `startEps()`'s `/CS { GS } bind
     * def`/`/CR { GR } bind def`), so the native `translate`/`rotate`
     * operators only affect this one piece of text, matching FLTK's
     * `GS %d %d translate %d rotate\n` exactly (including the same
     * angle negation -- PostScript's `rotate` is also clockwise for
     * positive angles, opposite of `fl_draw()`'s counterclockwise
     * convention). Calls this class's own 3-arg `draw()` at the
     * now-local origin `(0,0)`, the direct equivalent of FLTK
     * calling its own `transformed_draw()` -- this port's `draw()`
     * above already collapsed that function's role in (see its own doc
     * comment).
     */
    override void draw(int angle, const(char)[] str, int nChars, int x, int y)
    {
        output_.writef("GS %d %d translate %d rotate\n", x, y, -angle);
        draw(str, nChars, 0, 0);
        output_.write("GR\n");
    }

    /**
     * Draws an 8-bit-per-channel image via the `CII`/`GII` PostScript
     * operators (already transcribed verbatim into `psProlog2`, unused
     * until now). Ported from `Fl_PostScript_Graphics_Driver::draw_image
     * (const uchar*,int,int,int,int,int,int)` + the callback-based
     * `draw_image()`/`draw_image_mono()` it delegates to for the actual
     * RLE85-encoded emission, collapsed into one function here since
     * this port's `fl.draw.drawImage()` (the only real caller) has
     * already pre-cropped/pre-resampled `buf` to exactly `w`x`h` pixels
     * by the time this runs -- unlike FLTK, which can receive a
     * `buf` at one native resolution and a *different* requested
     * on-page size via its own `scale_for_image_()`, this port needs no
     * separate scale/translate transform: passing `w,h` as *both* the
     * `CII`/`GII` macros' `sx,sy` (on-page scale) *and* `px,py` (source
     * pixel dimensions) arguments makes the macro's own unit-square
     * image placement land exactly on `(x,y,w,h)` with no mismatch.
     * `d<3` (gray/gray+alpha) routes through `GII` instead of `CII`,
     * matching FLTK's own `abs(D)<3` split between `draw_image()`
     * and `draw_image_mono()`.
     *
     * This driver's `lang_level_` is always 2 (see `startEps()`'s own
     * doc comment), so FLTK's own `Fl_RGB_Image`-level real
     * transparency masking (`alpha_mask()`'s Floyd-Steinberg dithering
     * + the `CIM`/`level2_mask`/`pixmap_plot` machinery, `lang_level_ >
     * 2`-only) is genuinely dead code for this driver even in real
     * FLTK (`Fl_PostScript_Graphics_Driver::draw_rgb()`'s own
     * `if (lang_level_ <= 2 || !alpha_mask(...))` short-circuits before
     * `alpha_mask()` ever runs) -- not a simplification this port is
     * making, FLTK's own real level-2 behavior already skips it,
     * falling back to the same `d>3`-alpha-blended-against-`bg_r/g/b`
     * path this override uses for any `d==4`/`d==2` image, ported
     * faithfully from `draw_image()`'s own `if (lang_level_<3 &&
     * abs(D)>3)`/`draw_image_mono()`'s `abs(D)>1` blend branches.
     */
    override void drawImage(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        if (w <= 0 || h <= 0 || buf is null) return;
        if (l == 0) l = w * d;
        if (d < 3) { drawImageMono(buf, x, y, w, h, d, l); return; }

        output_.write("save\n");
        output_.writef("%g %g %g %g %d %d %s CII\n",
            cast(double) x, cast(double)(y + h), cast(double) w, cast(double)(-h), w, h,
            interpolate_ ? "true" : "false");

        auto rle = Rle85Encoder(output_);
        foreach (row; 0 .. h)
        {
            const(ubyte)* src = buf + row * l;
            foreach (col; 0 .. w)
            {
                ubyte r = src[0], g = src[1], b = src[2];
                if (d > 3)
                {
                    uint a2 = src[3];
                    uint a = 255 - a2;
                    r = cast(ubyte)((a2 * r + bgR_ * a) / 255);
                    g = cast(ubyte)((a2 * g + bgG_ * a) / 255);
                    b = cast(ubyte)((a2 * b + bgB_ * a) / 255);
                }
                rle.write(r);
                rle.write(g);
                rle.write(b);
                src += d;
            }
        }
        rle.close();
        output_.write("\nrestore\n");
    }

    /// The `d<3` (gray/gray+alpha) half of `drawImage()` above -- ported
    /// from `Fl_PostScript_Graphics_Driver::draw_image_mono(const
    /// uchar*,...)`'s callback-based body, same "no separate scale
    /// transform needed" simplification.
    private void drawImageMono(const(ubyte)* buf, int x, int y, int w, int h, int d, int l)
    {
        output_.write("save\n");
        output_.writef("%g %g %g %g %d %d %s GII\n",
            cast(double) x, cast(double)(y + h), cast(double) w, cast(double)(-h), w, h,
            interpolate_ ? "true" : "false");

        int bg = (bgR_ + bgG_ + bgB_) / 3;
        auto rle = Rle85Encoder(output_);
        foreach (row; 0 .. h)
        {
            const(ubyte)* src = buf + row * l;
            foreach (col; 0 .. w)
            {
                ubyte r = src[0];
                if (d > 1)
                {
                    uint a2 = src[1];
                    uint a = 255 - a2;
                    r = cast(ubyte)((a2 * r + bg * a) / 255);
                }
                rle.write(r);
                src += d;
            }
        }
        rle.close();
        output_.write("\nrestore\n");
    }

    /**
     * Draws a 1-bit bitmap via the `MI` PostScript operator (already in
     * `psProlog`, unused until now). Ported from
     * `Fl_PostScript_Graphics_Driver::draw_bitmap(Fl_Bitmap*,...)` --
     * including a real, faithfully-reproduced FLTK quirk: `bits` is
     * always the bitmap's *full* `dataW`x`dataH` data, `cx`/`cy`
     * genuinely ignored (FLTK's own `draw_bitmap()` reassigns its
     * local `WP`/`HP` -- the declared image dimensions the `MI`-
     * equivalent line uses -- to `bitmap->data_w()`/`data_h()` *after*
     * `scale_for_image_()` already computed the page-placement
     * transform from the *original*, caller-supplied `WP`/`HP`, so a
     * cropped `Fl_Bitmap::draw()` call still emits and places the whole
     * bitmap, just scaled as if it were the requested sub-rectangle --
     * an odd but real, unconditional FLTK behavior, not something
     * this port introduced). Unlike `drawImage()` above, this *does*
     * need an outer scale/translate wrapper (FLTK's own
     * `scale_for_image_()`, called once before the reassignment quirk
     * above ever applies): `MI` itself declares only the bitmap's own
     * native `dataW`x`dataH` pixel grid, so mapping that onto the
     * requested `(x,y,w,h)` destination rectangle needs a real
     * `translate(x,y) scale(w/dataW, h/dataH)` around it. Each row is
     * bit-reversed via `swapByte()` before RLE85 encoding -- PostScript's
     * `imagemask` expects each byte's bits MSB-first (bit 7 = leftmost
     * pixel), the opposite of this port's own `Bitmap.array` convention
     * (bit 0 = leftmost, same as FLTK's `Fl_Bitmap`), matching
     * FLTK's own `swap_byte()`/`swapped[16]` nibble-reversal table
     * exactly.
     */
    override void drawBitmap(const(ubyte)* bits, int dataW, int dataH, int x, int y, int w, int h, int cx, int cy)
    {
        if (dataW <= 0 || dataH <= 0 || bits is null || w <= 0 || h <= 0) return;

        output_.writef("GS %d %d translate %g %g scale\n",
            x, y, cast(double) w / dataW, cast(double) h / dataH);
        output_.writef("%d %d %d %d %d %d MI\n", 0, dataH, dataW, -dataH, dataW, dataH);

        int xx = (dataW + 7) / 8;
        auto rle = Rle85Encoder(output_);
        const(ubyte)* p = bits;
        foreach (i; 0 .. dataH * xx)
        {
            rle.write(swapByte(*p));
            p++;
        }
        rle.close();
        output_.write("\nGR\n");
    }

    // Bitwise reversal of a byte, one nibble at a time -- ported from
    // the file-scope `swapped[16]` table + `swap_byte()`.
    private static immutable ubyte[16] swappedNibble = [
        0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15
    ];
    private static ubyte swapByte(ubyte b)
    {
        return cast(ubyte)((swappedNibble[b & 0xF] << 4) | swappedNibble[b >> 4]);
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::start_eps()`. Skips
    /// the `%%Title:`/`%%CreationDate:` comment lines (cosmetic --
    /// FLTK's own `%%Title:` is conditional on a filename this
    /// class never has, since it's only ever constructed directly with
    /// an already-open `File`, and `%%CreationDate:` just adds
    /// wall-clock nondeterminism for no functional benefit) and the
    /// display-scale-factor block (`if (s != 1) ...` -- `fl.core.
    /// screenScale(int)` is real, but this driver doesn't consult it
    /// yet, same simplification
    /// `fl.image_surface.ImageSurface`'s ignored `highRes` parameter
    /// already makes).
    void startEps(int width, int height)
    {
        pw_ = width;
        ph_ = height;
        output_.write("%!PS-Adobe-3.0 EPSF-3.0\n");
        output_.write("%%Creator: (FLTK)\n");
        output_.writef("%%%%BoundingBox: 1 1 %d %d\n", width, height);
        output_.write("%%LanguageLevel: 2\n");
        output_.write("%%Pages: 1\n%%EndComments\n");
        output_.write("%%BeginProlog\n");
        output_.write("%%EndProlog\n");
        output_.write("save\n");
        output_.write("/FLTK 20 dict def FLTK begin\n"
            ~ "/x1 0 def /x2 0 def /y1 0 def /y2 0 def /x 0 def /y 0 def /dx 0 def /dy 0 def\n"
            ~ "/px 0 def /py 0 def /sx 0 def /sy 0 def /inter 0 def\n"
            ~ "/pixmap_sx 0 def  /pixmap_sy 0 def /pixmap_w 0 def /pixmap_h 0 def\n");
        output_.write(psProlog);
        output_.write(psProlog2);
        output_.write("/CS { GS } bind def\n");
        output_.write("/CR { GR } bind def\n");
        output_.write("GS\n");
        output_.writef("%g %g TR\n", 0.0, ph_);
        output_.write("1 -1 SC\n");
        lineStyle(0, 0, []);
        output_.write("GS GS\n");
    }

    /// Ported from `Fl_EPS_File_Surface::close()`'s driver-side half.
    /// Doesn't attempt FLTK's own `ferror()`-based error return
    /// (always `0`) -- same simplification `fl.svg_file_surface.
    /// SvgFileSurface.close()` already makes; a real I/O failure
    /// surfaces as a D exception from `flush()`/`close()` instead of a
    /// silently-ignored return code.
    void closeEps()
    {
        output_.write("GR\nend %matches begin of FLTK dict\n");
        output_.write("restore\n");
        output_.write("%%EOF\n");
        clipStack_ = [];
        output_.flush();
    }

    /// Ported from `Fl_EPS_File_Surface::origin(int, int)` ->
    /// `Fl_PostScript_Graphics_Driver::ps_origin()`.
    void psOrigin(int x, int y)
    {
        output_.writef("GR GR GS %d %d TR  %g %g SC %d %d TR %g rotate GS\n",
            leftMargin_, topMargin_, scaleX_, scaleY_, x, y, angle_);
    }

    /// Ported from `Fl_EPS_File_Surface::translate()` ->
    /// `Fl_PostScript_Graphics_Driver::ps_translate()`.
    void psTranslate(int x, int y)
    {
        output_.writef("GS %d %d translate GS\n", x, y);
    }

    /// Ported from `Fl_EPS_File_Surface::untranslate()` ->
    /// `Fl_PostScript_Graphics_Driver::ps_untranslate()`.
    void psUntranslate()
    {
        output_.write("GR GR\n");
    }

    /// Total page count the caller told `startPostscript()` to expect
    /// (`0` if unknown ahead of time). Ported from `pages_` -- used only
    /// by `endPostscript()`'s `%%Trailer`/`%%Pages:` decision, matching
    /// FLTK exactly.
    private int pagesRequested_;

    /// Pages actually emitted so far via `page()`. Ported from `nPages`.
    private int nPages_;

    /// `Page_Format | Page_Layout`, as passed to `startPostscript()`.
    /// Ported from `page_format_` -- `beginPage()`
    /// (`fl.postscript.PostscriptFileDevice`) passes this straight back
    /// into `page(int)` on every new page, matching FLTK's own
    /// `ps->page(ps->page_format_)`.
    int pageFormatCombined_;

    /// Clears per-page bookkeeping back to defaults. Ported from
    /// `Fl_PostScript_Graphics_Driver::reset()` -- FLTK's own body
    /// also resets its cached `Fl_Graphics_Driver::font()`/`size()`
    /// fields, which this port's `draw()` has no equivalent of at all
    /// (it reads `fl.draw.fl_font()`/`fl_size()` fresh on every call
    /// instead of caching a copy -- see `draw()`'s own doc comment), so
    /// there's nothing to reset there. Emits nothing to the PostScript
    /// stream itself, matching FLTK -- callers that need the reset
    /// line style actually *written* call `lineStyle(0, 0, [])`
    /// afterward, same as FLTK's own `reset(); ... line_style(0);`
    /// pairing in `page()`/`startPostscript()`.
    private void resetPageState()
    {
        clipStack_ = [];
        cr_ = cg_ = cb_ = 0;
        lastStyle_ = 0;
        lastWidth_ = 0;
        lastDashes_ = [];
    }

    /**
     * Ported from `Fl_PostScript_Graphics_Driver::start_postscript()`.
     * Always behaves as FLTK's own `lang_level_ == 2` default (this
     * driver never raises `lang_level_`, matching `startEps()`'s own
     * precedent) -- includes `psProlog`/`psProlog2` unconditionally,
     * skips `prolog_2_pixmap`/`prolog_3` (image-only), and always uses
     * the `GS`/`GR`-based `CS`/`CR` macros (FLTK's own `lang_level_
     * >= 3` branch, real `clipsave`/`cliprestore`, is never reached).
     */
    int startPostscript(int pageCount, PageFormat format, PageLayout layout)
    {
        leftMargin_ = format == a4 ? 18 : 12;
        topMargin_ = format == a4 ? 18 : 12;
        pageFormatCombined_ = format | layout;
        if (layout & landscape)
        {
            ph_ = pageFormats[format].width;
            pw_ = pageFormats[format].height;
        }
        else
        {
            pw_ = pageFormats[format].width;
            ph_ = pageFormats[format].height;
        }

        output_.write("%!PS-Adobe-3.0\n");
        output_.write("%%Creator: FLTK\n");
        output_.write("%%LanguageLevel: 2\n");
        pagesRequested_ = pageCount;
        if (pageCount != 0)
            output_.writef("%%%%Pages: %d\n", pageCount);
        else
            output_.write("%%Pages: (atend)\n");
        output_.writef("%%%%BeginFeature: *PageSize %s\n", pageFormats[format].name);
        output_.writef("<</PageSize[%d %d]>>setpagedevice\n",
            pageFormats[format].width, pageFormats[format].height);
        output_.write("%%EndFeature\n");
        output_.write("%%EndComments\n%%BeginProlog\n");
        output_.write(psProlog);
        output_.write(psProlog2);
        output_.write("/CS { GS } bind def\n");
        output_.write("/CR { GR } bind def\n");
        output_.write("%%EndProlog\n");
        output_.write("<< /Policies << /Pagesize 1 >> >> setpagedevice\n");

        resetPageState();
        nPages_ = 0;
        return 0;
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::page(double, double,
    /// int)`. `mediaFlags` combines `fl.paged_device.reversed` with
    /// `fl.paged_device.media` (see that module's own doc comment on
    /// why `Page_Format`/`Page_Layout` stay plain ints rather than real
    /// D enums -- this is exactly the OR-combination that requires it).
    /// The `lang_level_ == 2 ? int(pw - ph) : 0` FLTK ternary
    /// collapses to always `int(pw - ph)` here, same "`lang_level_`
    /// never leaves 2" simplification as `startPostscript()`.
    void page(double pw, double ph, int mediaFlags)
    {
        if (nPages_)
            output_.write("CR\nGR\nGR\nGR\nSP\nrestore\n");
        nPages_++;
        output_.writef("%%%%Page: %d %d\n", nPages_, nPages_);
        int bw = pw > ph ? cast(int) ph : cast(int) pw;
        int bh = pw > ph ? cast(int) pw : cast(int) ph;
        output_.writef("%%%%PageBoundingBox: 0 0 %d %d\n", bw, bh);
        output_.write(pw > ph ? "%%PageOrientation: Landscape\n" : "%%PageOrientation: Portrait\n");

        output_.write("%%BeginPageSetup\n");
        bool mediaAndLevel = (mediaFlags & media) != 0;
        if (mediaAndLevel)
        {
            int r = (mediaFlags & reversed) != 0 ? 2 : 0;
            output_.writef("<< /PageSize [%d %d] /Orientation %d>> setpagedevice\n",
                cast(int)(pw + .5), cast(int)(ph + .5), r);
        }
        output_.write("%%EndPageSetup\n");

        resetPageState();

        output_.write("save\n");
        output_.write("GS\n");
        output_.writef("%g %g TR\n", 0.0, ph_);
        output_.write("1 -1 SC\n");
        lineStyle(0, 0, []);
        output_.write("GS\n");

        if (!mediaAndLevel)
        {
            if (pw > ph)
            {
                if (mediaFlags & reversed)
                    output_.writef("-90 rotate %d 0 translate\n", cast(int)(-pw));
                else
                    output_.writef("90 rotate -%d -%d translate\n", cast(int)(pw - ph), cast(int) ph);
            }
            else if (mediaFlags & reversed)
                output_.writef("180 rotate %d %d translate\n", cast(int)(-pw), cast(int)(-ph));
        }
        output_.write("GS\nCS\n");
    }

    /// Ported from `Fl_PostScript_Graphics_Driver::page(int)`.
    void page(int combinedFormatAndLayout)
    {
        page(pw_, ph_, combinedFormatAndLayout & 0xFF00);
    }

    /// Ported from `Fl_PostScript_File_Device::scale()`'s driver-
    /// touching half -- unlike `psOrigin()`, deliberately omits the
    /// offset `TR` term, matching FLTK's own sequence exactly
    /// (`scale()`'s own doc comment: "This function also resets the
    /// origin of graphics functions at top left of printable page
    /// area").
    void psScale(double sx, double sy)
    {
        scaleX_ = sx;
        scaleY_ = sy;
        output_.writef("GR GR GS %d %d TR  %g %g SC %g rotate GS\n",
            leftMargin_, topMargin_, scaleX_, scaleY_, angle_);
    }

    /**
     * Ported from the non-pango half of `Fl_PostScript_File_Device::
     * end_job()`'s driver-touching logic: writes the multi-page
     * trailer (or the plain single-`GR`/`restore` EPS-style close if
     * `page()` was never called -- FLTK's own comment: "for eps
     * nPages is 0 so it is fine"), flushes, and resets state. Doesn't
     * reproduce FLTK's own `ferror()`-based error return (always
     * returns nothing meaningful to check) -- same simplification
     * `closeEps()`/`fl.svg_file_surface.SvgFileSurface.close()` already
     * make; a real I/O failure surfaces as a D exception instead. The
     * file-closing decision itself belongs to `PostscriptFileDevice`
     * (see that class's own `closesFile_`), not here, matching how
     * FLTK's own `close_cmd_`-vs-`fclose()` choice lives in
     * `Fl_PostScript_File_Device::end_job()`, one level up from this
     * driver.
     */
    void endPostscript()
    {
        if (nPages_)
        {
            output_.write("CR\nGR\nGR\nGR\nSP\n restore\n");
            if (pagesRequested_ == 0)
            {
                output_.write("%%Trailer\n");
                output_.writef("%%%%Pages: %d\n", nPages_);
            }
        }
        else
            output_.write("GR\n restore\n");
        output_.write("%%EOF");
        output_.flush();
        resetPageState();
    }
}

/**
 * Ported from `Fl_EPS_File_Surface` (`FL/Fl_PostScript.H`) -- see this
 * module's own top comment for what's cut relative to FLTK. Usage
 * mirrors FLTK's own documented example minus `draw_decorated_
 * window()` (see this class's own doc comment for why), e.g.:
 * ---
 * auto f = File("out.eps", "wb"); // binary mode: image/bitmap payloads
 *                                 // are ASCII85/RLE-encoded through this
 *                                 // same handle, and a text-mode "w"
 *                                 // handle's CRLF translation on Windows
 *                                 // would corrupt any embedded 0x0A byte
 *                                 // in that encoded stream, not just the
 *                                 // plain-text PostScript command lines
 * auto surf = new EpsFileSurface(200, 150, f);
 * SurfaceDevice.pushCurrent(surf);
 * fl_color(red);
 * fl_rectf(10, 10, 60, 40);
 * SurfaceDevice.popCurrent();
 * surf.close(); // the .eps file isn't complete until this runs
 * ---
 */
class EpsFileSurface : WidgetSurface
{
    private PostscriptGraphicsDriver psDriver_;
    private bool closed_;

    /// Ported from `Fl_EPS_File_Surface(int, int, FILE*, Fl_Color,
    /// Fl_PostScript_Close_Command)` -- the `closef` custom-close-
    /// function parameter isn't ported (no caller needs it, same as
    /// `fl.svg_file_surface.SvgFileSurface`'s own `closef`; `close()`/
    /// `~this()` always close the `File` directly). `background` is
    /// accepted for call-shape compatibility with FLTK (used there
    /// to blend transparent `Fl_RGB_Image` backgrounds) but has no
    /// effect yet -- images aren't dispatched by `PostscriptGraphicsDriver`
    /// at all (see that class's own doc comment), matching
    /// `ImageSurface`'s ignored `highRes` parameter precedent.
    this(int width, int height, File f, Color background = white)
    {
        auto driver = new PostscriptGraphicsDriver(f);
        super(driver);
        psDriver_ = driver;
        driver.startEps(width, height);
    }

    /// Ported from `~Fl_EPS_File_Surface()`: closes the file if the
    /// caller didn't already call `close()` explicitly.
    ~this()
    {
        if (!closed_) close();
    }

    /// The underlying file. Ported from `Fl_EPS_File_Surface::file()`.
    File file() { return psDriver_.file(); }

    /// Ported from `Fl_EPS_File_Surface::close()`. Safe to call more
    /// than once (matches `~this()`'s own guard).
    int close()
    {
        if (closed_) return 0;
        closed_ = true;
        psDriver_.closeEps();
        psDriver_.file().close();
        return 0;
    }

    /// Ported from `Fl_EPS_File_Surface::printable_rect()` -- always
    /// succeeds with the surface's own full size, unlike
    /// `WidgetSurface`'s always-failing base.
    override int printableRect(out int w, out int h) const
    {
        w = cast(int) psDriver_.pw_;
        h = cast(int) psDriver_.ph_;
        return 0;
    }

    /// Ported from `Fl_EPS_File_Surface::origin(int, int)`.
    override void origin(int x, int y)
    {
        psDriver_.psOrigin(x, y);
        super.origin(x, y);
    }

    /// Ported from `Fl_EPS_File_Surface::translate(int, int)`.
    protected override void translate(int x, int y)
    {
        psDriver_.psTranslate(x, y);
    }

    /// Ported from `Fl_EPS_File_Surface::untranslate()`.
    protected override void untranslate()
    {
        psDriver_.psUntranslate();
    }

    /// **Known, deliberate gap, same shape as `fl.svg_file_surface.
    /// SvgFileSurface`'s own**: `draw(Widget)`/`drawDecoratedWindow()`
    /// (both inherited from `WidgetSurface`) aren't safe to use on a
    /// real widget in general -- `PostscriptGraphicsDriver` doesn't
    /// dispatch images at all yet, so any widget whose `draw()` touches
    /// one (icons, `Label.image`) falls straight through to native
    /// Xlib and mixes real window pixels into what should have been
    /// pure EPS output. Drive the surface directly (see this module's
    /// own unittest) until images are covered too.
}

/**
 * Ported from `Fl_PostScript_File_Device` (`FL/Fl_PostScript.H` +
 * the shared, non-`#if USE_PANGO`-gated member functions in
 * `src/drivers/PostScript/Fl_PostScript.cxx`, after that file's own
 * cairo branch) -- multi-page PostScript output, either to a `File`
 * the caller already opened or to one chosen interactively via a real
 * `fl.native_file_chooser.NativeFileChooser` "Save As" dialog. Usage
 * mirrors FLTK's own documented `Fl_Printer` example (`FL/
 * Fl_Printer.H`'s header comment), minus the interactive printer/page-
 * setup dialog only `Fl_Printer` itself adds:
 * ---
 * auto dev = new PostscriptFileDevice();
 * if (dev.beginJob(1, a4, portrait) == 0)
 * {
 *     dev.beginPage();
 *     int w, h;
 *     dev.printableRect(w, h);
 *     fl_color(black);
 *     fl_rect(0, 0, w, h);
 *     dev.endPage();
 *     dev.endJob();
 * }
 * ---
 *
 * `fl.native_file_chooser.
 * NativeFileChooser` is real (`Status: Partial`, FLTK-fallback
 * backend only, but functionally complete for exactly the
 * `browseSaveFile`-plus-filter usage `beginJob()` needs below). See
 * `PORTING.md`'s `FL/Fl_PostScript.H` row for the full status.
 *
 * Not ported: `set_current()`/`end_current()`
 * (FLTK saves/restores the *display* driver's own cached
 * `font()`/`size()` fields across a print job, since printing can
 * change them FLTK's way -- `Fl_PostScript_Graphics_Driver::
 * font()` both forwards to the display driver for metrics *and*
 * writes `/name SF`/`size FS` PostScript operators as a side effect.
 * This port's `draw()` never calls `fl.draw.fl_font()`/`fl_size()`'s
 * *setters* at all -- only the getters, fresh on every call, see
 * `draw()`'s own doc comment -- so there is nothing for a print job to
 * disturb and nothing to restore); `close_command()` (the underlying
 * `FILE*(*)(FILE*)` customization hook collapsed into a plain
 * `closesFile_` bool instead, since no caller needs an arbitrary close
 * function, only "close it" vs. "the caller still owns it" -- see
 * `closesFile_`'s own doc comment); `start_job()` (a pure FLTK-1.3.x-
 * API-compatibility synonym of `begin_job()` with no behavior of its
 * own, same reasoning `fl.paged_device.PagedDevice` already skips
 * `start_job()`/`start_page()` for).
 */
class PostscriptFileDevice : PagedDevice
{
    private PostscriptGraphicsDriver psDriver_;

    /// Whether `endJob()` should close `psDriver_.output_` itself.
    /// Ported from FLTK's `close_cmd_`/`close_command()` mechanism
    /// -- see this class's own doc comment for why it's a plain `bool`
    /// here rather than a customizable close function. The file-
    /// chooser `beginJob()` overload sets this `true` (this class opened
    /// the file itself, matching FLTK's own default `close_cmd_ ==
    /// NULL` -> `fclose()`); the `File`-based overload sets it `false`
    /// (the caller still owns the file, matching FLTK's own
    /// `close_command(dont_close)`).
    private bool closesFile_ = true;

    /// Ported from `Fl_PostScript_File_Device()`.
    this()
    {
        psDriver_ = new PostscriptGraphicsDriver(File.init);
        super(psDriver_);
    }

    /// Ported from `Fl_PostScript_File_Device::file()`.
    File file() { return psDriver_.file(); }

    /**
     * Begins the session where all graphics requests go to a local
     * PostScript file the user picks interactively. Ported from
     * `Fl_PostScript_File_Device::begin_job(int, Page_Format,
     * Page_Layout)`: opens a real `NativeFileChooser` "Save As" dialog
     * (`browseSaveFile`, filtered to `*.ps`, `saveasConfirm |
     * useFilterExt` options -- matching FLTK's own `SAVEAS_CONFIRM
     * | USE_FILTER_EXT` exactly).
     * @return 0 if OK, 1 if the user cancelled the dialog, 2 if the
     * chosen file couldn't be opened for writing.
     */
    int beginJob(int pageCount, PageFormat format, PageLayout layout)
    {
        import fl.native_file_chooser : NativeFileChooser, BrowseType, saveasConfirm, useFilterExt;

        auto chooser = new NativeFileChooser(BrowseType.browseSaveFile);
        chooser.title("Select a .ps file");
        chooser.options(saveasConfirm | useFilterExt);
        chooser.filter("PostScript\t*.ps\n");
        if (chooser.show() != 0) return 1;
        auto filename = chooser.filename();
        if (filename.length == 0) return 1;

        File f;
        try
            // Binary, not text, mode -- a page's image/bitmap payloads
            // are ASCII85/RLE-encoded through this same handle, and a
            // text-mode handle's CRLF translation on Windows would
            // corrupt any embedded 0x0A byte in that encoded stream.
            f = File(filename, "wb");
        catch (Exception)
            return 2;

        psDriver_.output_ = f;
        closesFile_ = true;
        return psDriver_.startPostscript(pageCount, format, layout);
    }

    /**
     * Begins the session where all graphics requests go to `psOutput`,
     * a `File` the caller already opened and remains responsible for
     * closing -- `endJob()` won't close it. Ported from
     * `Fl_PostScript_File_Device::begin_job(FILE*, int, Page_Format,
     * Page_Layout)`.
     * @return always 0, matching FLTK.
     */
    int beginJob(File psOutput, int pageCount, PageFormat format, PageLayout layout)
    {
        psDriver_.output_ = psOutput;
        closesFile_ = false;
        return psDriver_.startPostscript(pageCount, format, layout);
    }

    /// Ported from `Fl_PostScript_File_Device::begin_job(int, int*,
    /// int*, char**)` -- FLTK's own doc comment: "Don't use with
    /// this class."
    override int beginJob(int pageCount, out int fromPage, out int toPage, out string errMessage)
    {
        return 1;
    }

    /// Ported from `Fl_PostScript_File_Device::margins()`.
    override void margins(out int left, out int top, out int right, out int bottom)
    {
        left = cast(int)(psDriver_.leftMargin_ / psDriver_.scaleX_ + .5);
        right = left;
        top = cast(int)(psDriver_.topMargin_ / psDriver_.scaleY_ + .5);
        bottom = top;
    }

    /// Ported from `Fl_PostScript_File_Device::printable_rect()`.
    override int printableRect(out int w, out int h) const
    {
        w = cast(int)((psDriver_.pw_ - 2 * psDriver_.leftMargin_) / psDriver_.scaleX_ + .5);
        h = cast(int)((psDriver_.ph_ - 2 * psDriver_.topMargin_) / psDriver_.scaleY_ + .5);
        return 0;
    }

    /// Ported from `Fl_PostScript_File_Device::origin(int, int)`. The
    /// getter overload (`origin(int*, int*)` FLTK, `WidgetSurface.
    /// origin(out int, out int)` here) needed no override -- FLTK's
    /// own body is a trivial pass-through to the base class, which is
    /// exactly what our inherited getter already does.
    override void origin(int x, int y)
    {
        psDriver_.psOrigin(x, y);
        super.origin(x, y);
    }

    /// Ported from `Fl_PostScript_File_Device::scale()`.
    override void scale(float scaleX, float scaleY = 0)
    {
        if (scaleY == 0) scaleY = scaleX;
        psDriver_.psScale(scaleX, scaleY);
    }

    /// Ported from `Fl_PostScript_File_Device::rotate()`. Reuses
    /// `psOrigin()` for the actual emission -- FLTK's own `rotate()`
    /// PostScript sequence and `ps_origin()`'s are identical once
    /// `angle` has been updated first, both include the current
    /// `x_offset`/`y_offset` (unlike `scale()`'s, which omits them --
    /// see `psScale()`'s own doc comment).
    override void rotate(float rotAngle)
    {
        psDriver_.angle_ = -rotAngle;
        // Was `int x, y; origin(x, y);` -- ambiguous overload resolution
        // between the inherited getter (`WidgetSurface.origin(out int,
        // out int) const`) and this class's own overridden setter
        // (`origin(int, int)` above): D resolves a call with two plain
        // `int` lvalue arguments to the *overridden setter* here, not
        // the getter, silently re-applying `origin(0, 0)` instead of
        // reading the actual current origin. See `fl.widget_surface.
        // WidgetSurface.draw()`'s own fix (same bug, confirmed via CTFE
        // repro) for the full story. Reading the fields directly
        // sidesteps the ambiguity entirely.
        psDriver_.psOrigin(xOffset_, yOffset_);
    }

    /// Ported from `Fl_PostScript_File_Device::translate(int, int)`.
    protected override void translate(int x, int y)
    {
        psDriver_.psTranslate(x, y);
    }

    /// Ported from `Fl_PostScript_File_Device::untranslate()`.
    protected override void untranslate()
    {
        psDriver_.psUntranslate();
    }

    /**
     * Ported from `Fl_PostScript_File_Device::begin_page()`. `xOffset_`/
     * `yOffset_` are reset directly (not via the `origin()` setter) so
     * as not to re-emit `psOrigin()`'s sequence on top of the fresh
     * coordinate system `page()` (called just above) already
     * established -- matching FLTK's own direct `x_offset = 0;
     * y_offset = 0;` field writes exactly.
     */
    override int beginPage()
    {
        SurfaceDevice.pushCurrent(this);
        psDriver_.page(psDriver_.pageFormatCombined_);
        xOffset_ = 0;
        yOffset_ = 0;
        psDriver_.scaleX_ = 1;
        psDriver_.scaleY_ = 1;
        psDriver_.angle_ = 0;
        psDriver_.output_.writef("GR GR GS %d %d translate GS\n",
            psDriver_.leftMargin_, psDriver_.topMargin_);
        return 0;
    }

    /// Ported from `Fl_PostScript_File_Device::end_page()`.
    override int endPage()
    {
        SurfaceDevice.popCurrent();
        return 0;
    }

    /// Ported from `Fl_PostScript_File_Device::end_job()` -- see
    /// `PostscriptGraphicsDriver.endPostscript()`'s own doc comment for
    /// what's simplified in the file-writing half; `closesFile_`
    /// decides the close here, same split as FLTK's own `close_cmd_
    /// ? ... : fclose(...)`.
    override void endJob()
    {
        psDriver_.endPostscript();
        if (closesFile_) psDriver_.output_.close();
    }
}

unittest
{
    import fl.image_surface : SurfaceDevice;
    import fl.enumerations : red, blue, black, green;
    import graphicsDriver = fl.graphics_driver;
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind;

    auto path = buildPath(tempDir(), "fldtk-eps-test-" ~ randomUUID().toString() ~ ".eps");
    scope (exit) if (exists(path)) remove(path);

    {
        auto f = File(path, "wb"); // binary: see EpsFileSurface's own doc comment on why
        auto surf = new EpsFileSurface(200, 150, f);
        SurfaceDevice.pushCurrent(surf);
        assert(graphicsDriver.currentDriver !is null);

        fldraw.fl_color(red);
        fldraw.fl_rectf(10, 10, 60, 40);
        fldraw.fl_color(blue);
        fldraw.fl_rect(80, 10, 60, 40);
        fldraw.fl_color(black);
        fldraw.fl_line(10, 70, 190, 70);
        fldraw.fl_color(green);
        fldraw.fl_polygon(10, 100, 40, 140, 10, 140);

        SurfaceDevice.popCurrent();
        assert(graphicsDriver.currentDriver is null); // back to native

        surf.close();
    }

    assert(exists(path));
    auto text = readText(path);
    assert(text.canFind("%!PS-Adobe-3.0 EPSF-3.0"));
    assert(text.canFind("%%BoundingBox: 1 1 200 150"));
    assert(text.canFind("FR\n")); // fl_rectf() -> rectf() -> FR
    assert(text.canFind("MT\n")); // fl_rect()/fl_line()/fl_polygon() all path through moveto
    assert(text.canFind("%%EOF"));
}

unittest
{
    // Exercises line_style, clipping, arc/pie, the vertex-path end_*()
    // family (via fl_begin_*()/vertex()/fl_end_*()), and text.
    import fl.image_surface : SurfaceDevice;
    import fl.enumerations : black, red, helvetica, lineDash;
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind;

    auto path = buildPath(tempDir(), "fldtk-eps-test2-" ~ randomUUID().toString() ~ ".eps");
    scope (exit) if (exists(path)) remove(path);

    {
        auto f = File(path, "wb"); // binary: see EpsFileSurface's own doc comment on why
        auto surf = new EpsFileSurface(200, 200, f);
        SurfaceDevice.pushCurrent(surf);

        fldraw.fl_color(black);
        fldraw.lineStyle(lineDash, 2);
        fldraw.fl_line(0, 0, 50, 0);
        fldraw.lineStyle(0);

        fldraw.pushClip(0, 0, 100, 100);
        fldraw.popClip();

        fldraw.fl_color(red);
        fldraw.fl_arc(10, 10, 40, 40, 0, 90);
        fldraw.fl_pie(60, 10, 40, 40, 0, 360);

        fldraw.beginPolygon();
        fldraw.vertex(20, 80);
        fldraw.vertex(60, 80);
        fldraw.vertex(40, 110);
        fldraw.endPolygon();

        fldraw.beginLine();
        fldraw.vertex(0, 150);
        fldraw.vertex(50, 150);
        fldraw.vertex(50, 190);
        fldraw.endLine();

        fldraw.fl_font(helvetica, 14);
        fldraw.fl_draw("Hi", 100, 150);

        SurfaceDevice.popCurrent();
        surf.close();
    }

    auto text = readText(path);
    assert(text.canFind("setdash"));
    assert(text.canFind("CL\n")); // pushClip()'s clip rect
    assert(text.canFind(" arc\n")); // the outline arc()
    assert(text.canFind(" arcn\n") || text.canFind(" arc\n")); // pie()'s full-circle case
    assert(text.canFind("EFP")); // endPolygon()
    assert(text.canFind("ELP") || text.canFind("ECP")); // endLine()
    assert(text.canFind("/Helvetica2B SF"));
    assert(text.canFind("show_pos_width"));
}

unittest
{
    // Exercises PostscriptFileDevice's real multi-page path via the
    // File-based beginJob() overload -- the interactive
    // NativeFileChooser overload needs a live event loop/display, not
    // exercised headlessly here (same reasoning fl.native_file_chooser's
    // own tests don't drive show() either).
    import fl.paged_device : a4, portrait;
    import fl.enumerations : black, red;
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind;

    auto path = buildPath(tempDir(), "fldtk-ps-file-test-" ~ randomUUID().toString() ~ ".ps");
    scope (exit) if (exists(path)) remove(path);

    {
        auto f = File(path, "wb"); // binary: see EpsFileSurface's own doc comment on why
        auto dev = new PostscriptFileDevice();
        assert(dev.beginJob(f, 2, a4, portrait) == 0);

        assert(dev.beginPage() == 0);
        int w, h;
        assert(dev.printableRect(w, h) == 0);
        assert(w > 0 && h > 0);
        fldraw.fl_color(black);
        fldraw.fl_rect(0, 0, w, h);
        assert(dev.endPage() == 0);

        assert(dev.beginPage() == 0);
        fldraw.fl_color(red);
        fldraw.fl_rectf(10, 10, 50, 30);
        assert(dev.endPage() == 0);

        dev.endJob(); // File-based beginJob() -> closesFile_ == false, doesn't close f
        f.close();
    }

    auto text = readText(path);
    assert(text.canFind("%!PS-Adobe-3.0\n"));
    assert(text.canFind("%%Pages: 2\n"));
    assert(text.canFind("%%Page: 1 1\n"));
    assert(text.canFind("%%Page: 2 2\n"));
    assert(text.canFind("FR\n")); // fl_rectf() on page 2
    assert(text.canFind("%%EOF"));
}

unittest
{
    // drawImage()/drawBitmap() (GraphicsDriver.drawImage()/drawBitmap())
    // via a real RGBImage.draw()/Bitmap.draw()
    // dispatched through fl.draw.drawImage()/drawBitmapFixed(), the
    // same real call path a live widget with an image label would use.
    import fl.image : RGBImage;
    import fl.bitmap : Bitmap;
    import fl.image_surface : SurfaceDevice;
    import std.file : tempDir, exists, remove, readText;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import std.algorithm : canFind;

    auto path = buildPath(tempDir(), "fldtk-eps-image-test-" ~ randomUUID().toString() ~ ".eps");
    scope (exit) if (exists(path)) remove(path);

    {
        auto f = File(path, "wb"); // binary: see EpsFileSurface's own doc comment on why
        auto surf = new EpsFileSurface(100, 100, f);
        SurfaceDevice.pushCurrent(surf);

        // A tiny 4x4 RGB image -- exercises the CII/drawImage() path.
        ubyte[] rgb = new ubyte[4 * 4 * 3];
        foreach (i; 0 .. 4 * 4)
        {
            rgb[i * 3] = 200; rgb[i * 3 + 1] = 50; rgb[i * 3 + 2] = 50;
        }
        auto img = new RGBImage(rgb, 4, 4, 3);
        img.draw(10, 10, 4, 4);

        // A tiny 8x8 1-bit bitmap (checkerboard) -- exercises the
        // MI/drawBitmap() path.
        ubyte[] bits = [0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA];
        auto bm = new Bitmap(bits, 8, 8);
        bm.draw(30, 30, 8, 8);

        SurfaceDevice.popCurrent();
        surf.close();
    }

    auto text = readText(path);
    assert(text.canFind(" CII\n")); // RGBImage.draw() -> fl_draw_image() -> drawImage()
    assert(text.canFind(" MI\n")); // Bitmap.draw() -> drawBitmapFixed() -> drawBitmap()
    assert(text.canFind("~>")); // Rle85Encoder's own EOD marker, at least twice (image + bitmap)
    assert(text.canFind("%%EOF"));
}

