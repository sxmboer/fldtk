/*
 * Fluid's own per-node-type icon table -- ported from FLTK's
 * `fluid/rsrcs/pixmaps.h`/`.cxx`. `pixmapFor(type_name)` looks up the
 * small 16x16 icon for a given `Node.typeName` (e.g. "Fl_Button"),
 * used by both the widget palette (`function_panel.fl`'s buttons, via
 * `o.image(pixmapFor("Fl_Button"))`, matching FLTK's own
 * `o->image(pixmap_for("Fl_Button"))` one-for-one) and the node
 * browser's own per-row icon (`node_browser.d`, via `fl.tree_item.
 * TreeItem.usericon()`, already real).
 *
 * The icons are SVG files in `source/fluid/pixmaps_svg/` (one per
 * FLTK `fluid/pixmaps/*.xpm`, same name, same 32x32 design), embedded
 * at compile time with a string import (`dub.sdl`'s `stringImportPaths
 * "pixmaps_svg"`) and shown at 16x16. Where FLTK scales a bitmap down
 * (`new Fl_Pixmap(xpm_data); pm->scale(16, 16);`), `fl.svg_image.
 * SvgImage` draws the vector image at the screen's scale, so the icons
 * stay sharp at any desktop scale or Ctrl +/- zoom.
 *
 * `loadPixmaps()` matches FLTK's own function name and one-shot
 * call-once-at-startup shape (`Fluid.cxx`'s `make_main_window()`) --
 * called from `gui_main.d`'s `runEditor()`. Also registers `fd_zoom`,
 * a drawn (not pixmap) diagonal
 * zoom-cross glyph registered as an `fl.symbols` `@`-symbol, unrelated
 * to the icon *table* the rest of this file is about; see `fdZoom()`'s
 * own doc comment below.
 */
module fluid.pixmaps;

import fl.image : Image;
import fl.svg_image : SvgImage;
import fl.enumerations : Color;
import fl.draw;
import fl.symbols : addSymbol;

Image bindPixmap;
Image lockPixmap;
Image protectedPixmap;
Image invisiblePixmap;
Image compressedPixmap;

/// Icons for node types, keyed by `Node.typeName` (e.g. "Fl_Button").
private Image[string] pixmaps_;

/// Returns the icon for `typeName`, or `null` if none is registered --
/// matches FLTK's own `nullptr`-on-miss contract exactly.
///
/// This table is keyed by FLTK's own real type-name strings (e.g.
/// "Fl_Group", matching `pixmaps.cxx`'s own table exactly), but every
/// caller here (`node_browser.d`'s `Node.typeName`, `function_panel.fl`'s
/// own `o.typeName("Group")` calls) uses this *dialect's* own short
/// keywords instead -- `fluid.factory`'s registry accepts both a
/// `"Fl_" ~ bareName` form and a bare/camelCase alias for the same
/// node kind (see that module's own `reg()` helper), and it's the
/// alias that's actually written throughout this project's own `.fl`
/// files. Falls back to trying `"Fl_" ~ typeName` for the common case
/// (covers every type whose alias is just its FLTK name with the
/// prefix removed, e.g. "Group" -> "Fl_Group"); a fixed, explicit list
/// covers the real exceptions (`factory.d`'s own second `registry[...]
/// =` line for a type, where the alias also drops an underscore the
/// FLTK name keeps, e.g. "ReturnButton" vs "Fl_Return_Button").
Image pixmapFor(string typeName)
{
    if (auto p = typeName in pixmaps_) return *p;
    if (auto p = ("Fl_" ~ typeName) in pixmaps_) return *p;
    return null;
}

/// The icon `pixmaps_svg/<name>.svg`, shown at 16x16.
private Image load(string name)()
{
    auto img = new SvgImage(null, import(name ~ ".svg"));
    img.scale(16, 16);
    return img;
}

/// Populates every icon -- call once at startup (`gui_main.d`'s
/// `runEditor()`, matching FLTK's own `make_main_window()` call
/// site).
void loadPixmaps()
{
    bindPixmap = load!"bind";
    lockPixmap = load!"lock";
    protectedPixmap = load!"protected";
    invisiblePixmap = load!"invisible";
    compressedPixmap = load!"compressed";

    pixmaps_["Fl_Window"] = load!"flWindow";
    pixmaps_["Fl_Button"] = load!"flButton";
    pixmaps_["Fl_Check_Button"] = load!"flCheckButton";
    pixmaps_["Fl_Round_Button"] = load!"flRoundButton";

    pixmaps_["Fl_Box"] = load!"flBox";
    pixmaps_["Fl_Group"] = load!"flGroup";
    pixmaps_["Function"] = load!"flFunction";
    pixmaps_["code"] = load!"flCode";
    pixmaps_["codeblock"] = load!"flCodeBlock";
    pixmaps_["decl"] = load!"flDeclaration";

    pixmaps_["declblock"] = load!"flDeclarationBlock";
    pixmaps_["class"] = load!"flClass";
    pixmaps_["Fl_Tabs"] = load!"flTabs";
    pixmaps_["Fl_Input"] = load!"flInput";
    pixmaps_["Fl_Choice"] = load!"flChoice";

    pixmaps_["MenuItem"] = load!"flMenuitem";
    pixmaps_["Fl_Menu_Bar"] = load!"flMenubar";
    pixmaps_["Submenu"] = load!"flSubmenu";
    pixmaps_["Fl_Scroll"] = load!"flScroll";
    pixmaps_["Fl_Tile"] = load!"flTile";
    pixmaps_["Fl_Wizard"] = load!"flWizard";

    pixmaps_["Fl_Pack"] = load!"flPack";
    pixmaps_["Fl_Return_Button"] = load!"flReturnButton";
    pixmaps_["Fl_Light_Button"] = load!"flLightButton";
    pixmaps_["Fl_Repeat_Button"] = load!"flRepeatButton";
    pixmaps_["Fl_Menu_Button"] = load!"flMenuButton";

    pixmaps_["Fl_Output"] = load!"flOutput";
    pixmaps_["Fl_Text_Display"] = load!"flTextDisplay";
    pixmaps_["Fl_Text_Editor"] = load!"flTextEdit";
    pixmaps_["Fl_File_Input"] = load!"flFileInput";
    pixmaps_["Fl_Browser"] = load!"flBrowser";

    pixmaps_["Fl_Check_Browser"] = load!"flCheckBrowser";
    pixmaps_["Fl_File_Browser"] = load!"flFileBrowser";
    pixmaps_["Fl_Clock"] = load!"flClock";
    pixmaps_["Fl_Help_View"] = load!"flHelp";
    pixmaps_["Fl_Progress"] = load!"flProgress";

    pixmaps_["Fl_Slider"] = load!"flSlider";
    pixmaps_["Fl_Scrollbar"] = load!"flScrollBar";
    pixmaps_["Fl_Value_Slider"] = load!"flValueSlider";
    pixmaps_["Fl_Adjuster"] = load!"flAdjuster";
    pixmaps_["Fl_Counter"] = load!"flCounter";

    pixmaps_["Fl_Dial"] = load!"flDial";
    pixmaps_["Fl_Roller"] = load!"flRoller";
    pixmaps_["Fl_Value_Input"] = load!"flValueInput";
    pixmaps_["Fl_Value_Output"] = load!"flValueOutput";
    pixmaps_["comment"] = load!"flComment";

    pixmaps_["Fl_Spinner"] = load!"flSpinner";
    pixmaps_["widget_class"] = load!"flWidgetClass";
    pixmaps_["data"] = load!"flData";
    pixmaps_["Fl_Tree"] = load!"flTree";
    pixmaps_["Fl_Table"] = load!"flTable";

    pixmaps_["Fl_Terminal"] = load!"flSimpleTerminal";
    pixmaps_["Fl_Input_Choice"] = load!"flInputChoice";
    pixmaps_["CheckMenuItem"] = load!"flCheckMenuitem";
    pixmaps_["RadioMenuItem"] = load!"flRadioMenuitem";

    pixmaps_["Fl_Flex"] = load!"flFlex";
    pixmaps_["Fl_Grid"] = load!"flGrid";

    // Explicit aliases for the real exceptions `pixmapFor()`'s own
    // "Fl_" ~ typeName fallback can't cover -- `fluid.factory`'s own
    // second `registry[...] =` line for each of these types drops an
    // underscore the FLTK name (and this table's own key, just
    // above) keeps, so "Fl_" ~ "ReturnButton" ("Fl_ReturnButton")
    // would never match this table's real "Fl_Return_Button" key.
    // Every entry here mirrors one of `factory.d`'s own alias
    // registrations exactly -- see that module's own `reg()` calls.
    pixmaps_["ReturnButton"] = pixmaps_["Fl_Return_Button"];
    pixmaps_["LightButton"] = pixmaps_["Fl_Light_Button"];
    pixmaps_["CheckButton"] = pixmaps_["Fl_Check_Button"];
    pixmaps_["RoundButton"] = pixmaps_["Fl_Round_Button"];
    pixmaps_["ValueOutput"] = pixmaps_["Fl_Value_Output"];
    pixmaps_["ValueSlider"] = pixmaps_["Fl_Value_Slider"];
    pixmaps_["ValueInput"] = pixmaps_["Fl_Value_Input"];
    pixmaps_["TextEditor"] = pixmaps_["Fl_Text_Editor"];
    pixmaps_["TextDisplay"] = pixmaps_["Fl_Text_Display"];
    pixmaps_["MenuButton"] = pixmaps_["Fl_Menu_Button"];
    pixmaps_["MenuBar"] = pixmaps_["Fl_Menu_Bar"];
    pixmaps_["InputChoice"] = pixmaps_["Fl_Input_Choice"];
    pixmaps_["RepeatButton"] = pixmaps_["Fl_Repeat_Button"];
    pixmaps_["FileInput"] = pixmaps_["Fl_File_Input"];
    pixmaps_["CheckBrowser"] = pixmaps_["Fl_Check_Browser"];
    pixmaps_["FileBrowser"] = pixmaps_["Fl_File_Browser"];
    pixmaps_["HelpView"] = pixmaps_["Fl_Help_View"];

    addSymbol("fd_zoom", &fdZoom, true);
    addSymbol("fd_beaker", &fdBeaker, true);
    addSymbol("fd_user", &fdUser, true);
    addSymbol("fd_project", &fdProject, true);
    addSymbol("fd_file", &fdFile, true);
}

/// Ported from `fd_beaker()` (`fluid/app/Snap_Action.cxx`) -- a small
/// beaker, the symbol for a layout suite built into Fluid.
private void fdBeaker(Color c)
{
    fl_color(cast(Color) 221);
    beginPolygon();
    vertex(-0.6, 0.2);
    vertex(-0.9, 0.8);
    vertex(-0.8, 0.9);
    vertex(0.8, 0.9);
    vertex(0.9, 0.8);
    vertex(0.6, 0.2);
    endPolygon();
    fl_color(c);
    beginLine();
    vertex(-0.3, -0.9);
    vertex(-0.2, -0.8);
    vertex(-0.2, -0.2);
    vertex(-0.9, 0.8);
    vertex(-0.8, 0.9);
    vertex(0.8, 0.9);
    vertex(0.9, 0.8);
    vertex(0.2, -0.2);
    vertex(0.2, -0.8);
    vertex(0.3, -0.9);
    endLine();
}

/// Ported from `fd_user()` -- a user silhouette, the symbol for a
/// user-preference storage location.
private void fdUser(Color c)
{
    fl_color(cast(Color) 245);
    beginComplexPolygon();
    fl_arc(0.1, 0.9, 0.8, 0.0, 80.0);
    fl_arc(0.0, -0.5, 0.4, -65.0, 245.0);
    fl_arc(-0.1, 0.9, 0.8, 100.0, 180.0);
    endComplexPolygon();
    fl_color(c);
    beginLine();
    fl_arc(0.1, 0.9, 0.8, 0.0, 80.0);
    fl_arc(0.0, -0.5, 0.4, -65.0, 245.0);
    fl_arc(-0.1, 0.9, 0.8, 100.0, 180.0);
    endLine();
}

/// Ported from `fd_project()` -- a document with a folded corner, the
/// symbol for storage in the `.fl` project file.
private void fdProject(Color c)
{
    import fl.enumerations : light2;

    Color fc = light2;
    fl_color(fc);
    beginComplexPolygon();
    vertex(-0.7, -1.0);
    vertex(0.1, -1.0);
    vertex(0.1, -0.4);
    vertex(0.7, -0.4);
    vertex(0.7, 1.0);
    vertex(-0.7, 1.0);
    endComplexPolygon();

    fl_color(lighter(fc));
    beginPolygon();
    vertex(0.1, -1.0);
    vertex(0.1, -0.4);
    vertex(0.7, -0.4);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(-0.7, -1.0);
    vertex(0.1, -1.0);
    vertex(0.1, -0.4);
    vertex(0.7, -0.4);
    vertex(0.7, 1.0);
    vertex(-0.7, 1.0);
    endLoop();

    beginLine();
    vertex(0.1, -1.0);
    vertex(0.7, -0.4);
    endLine();
}

/// Ported from `fd_file()` -- a 3.5" floppy disk, the symbol for storage
/// in an external file.
private void fdFile(Color c)
{
    import fl.enumerations : light2, dark3;

    Color fl = light2;
    Color fc = dark3;
    fl_color(fc);
    beginPolygon(); // case
    vertex(-0.9, -1.0);
    vertex(0.9, -1.0);
    vertex(1.0, -0.9);
    vertex(1.0, 0.9);
    vertex(0.9, 1.0);
    vertex(-0.9, 1.0);
    vertex(-1.0, 0.9);
    vertex(-1.0, -0.9);
    endPolygon();

    fl_color(lighter(fl));
    beginPolygon(); // slider
    vertex(-0.7, -1.0);
    vertex(0.7, -1.0);
    vertex(0.7, -0.4);
    vertex(-0.7, -0.4);
    endPolygon();

    beginPolygon(); // label
    vertex(-0.7, 0.0);
    vertex(0.7, 0.0);
    vertex(0.7, 1.0);
    vertex(-0.7, 1.0);
    endPolygon();

    fl_color(fc);
    beginPolygon(); // slot
    vertex(-0.5, -0.9);
    vertex(-0.3, -0.9);
    vertex(-0.3, -0.5);
    vertex(-0.5, -0.5);
    endPolygon();

    fl_color(darker(c));
    beginLoop();
    vertex(-0.9, -1.0);
    vertex(0.9, -1.0);
    vertex(1.0, -0.9);
    vertex(1.0, 0.9);
    vertex(0.9, 1.0);
    vertex(-0.9, 1.0);
    vertex(-1.0, 0.9);
    vertex(-1.0, -0.9);
    endLoop();
}

/// Ported from `fluid::rsrcs::fd_zoom()` (`fluid/rsrcs/pixmaps.cxx`) --
/// a small drawn (not pixmap) diagonal zoom-cross glyph, registered as
/// an `fl.symbols` `@`-symbol (matching FLTK's own `fl_add_symbol(
/// "fd_zoom", fd_zoom, 1)`) rather than living in this file's own
/// icon table, since it's a vector glyph, not a bitmap. The Shell tab's
/// "open the big code editor" button (`settings_panel.fl`) references
/// it by FLTK's own real label, `@+1fd_zoom`, which fits the button's real
/// 22x22 size, unlike a plain `"Zoom..."` text label.
private void fdZoom(Color c)
{
    enum al = 0.45, sl = 0.3;

    fl_color(c);

    beginLine();
    vertex(-1.0, -al);
    vertex(-1.0, -1.0);
    vertex(-al, -1.0);
    endLine();
    beginLine();
    vertex(-1.0, -1.0);
    vertex(-sl, -sl);
    endLine();

    beginLine();
    vertex(1.0, -al);
    vertex(1.0, -1.0);
    vertex(al, -1.0);
    endLine();
    beginLine();
    vertex(1.0, -1.0);
    vertex(sl, -sl);
    endLine();

    beginLine();
    vertex(-1.0, al);
    vertex(-1.0, 1.0);
    vertex(-al, 1.0);
    endLine();
    beginLine();
    vertex(-1.0, 1.0);
    vertex(-sl, sl);
    endLine();

    beginLine();
    vertex(1.0, al);
    vertex(1.0, 1.0);
    vertex(al, 1.0);
    endLine();
    beginLine();
    vertex(1.0, 1.0);
    vertex(sl, sl);
    endLine();
}

unittest
{
    loadPixmaps();
    assert(bindPixmap !is null);
    assert(pixmapFor("Fl_Button") !is null);
    assert(pixmapFor("Fl_Grid") !is null);
    assert(pixmapFor("NoSuchType") is null);
    assert(pixmapFor("Fl_Button").w() == 16);
    assert(pixmapFor("Fl_Button").h() == 16);

    // The "Fl_" ~ typeName fallback -- covers every type this
    // dialect's own short alias matches its FLTK name minus the
    // prefix exactly (the common case, no explicit alias entry
    // needed): "Group" -> "Fl_Group", matching `function_panel.fl`'s
    // own `o.typeName("Group")` value.
    assert(pixmapFor("Group") is pixmapFor("Fl_Group"));
    assert(pixmapFor("Choice") is pixmapFor("Fl_Choice"));
    assert(pixmapFor("Box") is pixmapFor("Fl_Box"));

    // The explicit-alias exceptions -- `factory.d`'s own second
    // `registry[...] =` line drops an underscore the FLTK name
    // keeps, so the "Fl_" ~ typeName fallback alone can't cover these.
    assert(pixmapFor("ReturnButton") is pixmapFor("Fl_Return_Button"));
    assert(pixmapFor("TextDisplay") is pixmapFor("Fl_Text_Display"));
    assert(pixmapFor("MenuBar") is pixmapFor("Fl_Menu_Bar"));
    assert(pixmapFor("InputChoice") is pixmapFor("Fl_Input_Choice"));
}
