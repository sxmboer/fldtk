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
 * The 62 embedded XPMs backing this table live in `fluid.pixmaps_xpm`
 * (mechanically transliterated from FLTK's real `fluid/pixmaps/
 * *.xpm` files, byte-for-byte identical row content, see that module's
 * own top comment) -- kept in a separate module purely so this file
 * stays readable; nothing here needed to invent a new embedding
 * mechanism, `fl.pixmap.Pixmap(const(string)[] data)` and `fl.image.
 * Image.scale()` were both already real, exactly matching FLTK's
 * `new Fl_Pixmap(xpm_data); pm->scale(16, 16);` pair.
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

import fl.pixmap : Pixmap;
import fl.enumerations : Color;
import fl.draw;
import fl.symbols : addSymbol;

import fluid.pixmaps_xpm;

Pixmap bindPixmap;
Pixmap lockPixmap;
Pixmap protectedPixmap;
Pixmap invisiblePixmap;
Pixmap compressedPixmap;

/// Icons for node types, keyed by `Node.typeName` (e.g. "Fl_Button").
private Pixmap[string] pixmaps_;

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
Pixmap pixmapFor(string typeName)
{
    if (auto p = typeName in pixmaps_) return *p;
    if (auto p = ("Fl_" ~ typeName) in pixmaps_) return *p;
    return null;
}

private Pixmap load(const(string)[] xpmData)
{
    auto pm = new Pixmap(xpmData);
    pm.scale(16, 16);
    return pm;
}

/// Populates every icon -- call once at startup (`gui_main.d`'s
/// `runEditor()`, matching FLTK's own `make_main_window()` call
/// site).
void loadPixmaps()
{
    bindPixmap = load(bindXpm);
    lockPixmap = load(lockXpm);
    protectedPixmap = load(protectedXpm);
    invisiblePixmap = load(invisibleXpm);
    compressedPixmap = load(compressedXpm);

    pixmaps_["Fl_Window"] = load(flWindowXpm);
    pixmaps_["Fl_Button"] = load(flButtonXpm);
    pixmaps_["Fl_Check_Button"] = load(flCheckButtonXpm);
    pixmaps_["Fl_Round_Button"] = load(flRoundButtonXpm);

    pixmaps_["Fl_Box"] = load(flBoxXpm);
    pixmaps_["Fl_Group"] = load(flGroupXpm);
    pixmaps_["Function"] = load(flFunctionXpm);
    pixmaps_["code"] = load(flCodeXpm);
    pixmaps_["codeblock"] = load(flCodeBlockXpm);
    pixmaps_["decl"] = load(flDeclarationXpm);

    pixmaps_["declblock"] = load(flDeclarationBlockXpm);
    pixmaps_["class"] = load(flClassXpm);
    pixmaps_["Fl_Tabs"] = load(flTabsXpm);
    pixmaps_["Fl_Input"] = load(flInputXpm);
    pixmaps_["Fl_Choice"] = load(flChoiceXpm);

    pixmaps_["MenuItem"] = load(flMenuitemXpm);
    pixmaps_["Fl_Menu_Bar"] = load(flMenubarXpm);
    pixmaps_["Submenu"] = load(flSubmenuXpm);
    pixmaps_["Fl_Scroll"] = load(flScrollXpm);
    pixmaps_["Fl_Tile"] = load(flTileXpm);
    pixmaps_["Fl_Wizard"] = load(flWizardXpm);

    pixmaps_["Fl_Pack"] = load(flPackXpm);
    pixmaps_["Fl_Return_Button"] = load(flReturnButtonXpm);
    pixmaps_["Fl_Light_Button"] = load(flLightButtonXpm);
    pixmaps_["Fl_Repeat_Button"] = load(flRepeatButtonXpm);
    pixmaps_["Fl_Menu_Button"] = load(flMenuButtonXpm);

    pixmaps_["Fl_Output"] = load(flOutputXpm);
    pixmaps_["Fl_Text_Display"] = load(flTextDisplayXpm);
    pixmaps_["Fl_Text_Editor"] = load(flTextEditXpm);
    pixmaps_["Fl_File_Input"] = load(flFileInputXpm);
    pixmaps_["Fl_Browser"] = load(flBrowserXpm);

    pixmaps_["Fl_Check_Browser"] = load(flCheckBrowserXpm);
    pixmaps_["Fl_File_Browser"] = load(flFileBrowserXpm);
    pixmaps_["Fl_Clock"] = load(flClockXpm);
    pixmaps_["Fl_Help_View"] = load(flHelpXpm);
    pixmaps_["Fl_Progress"] = load(flProgressXpm);

    pixmaps_["Fl_Slider"] = load(flSliderXpm);
    pixmaps_["Fl_Scrollbar"] = load(flScrollBarXpm);
    pixmaps_["Fl_Value_Slider"] = load(flValueSliderXpm);
    pixmaps_["Fl_Adjuster"] = load(flAdjusterXpm);
    pixmaps_["Fl_Counter"] = load(flCounterXpm);

    pixmaps_["Fl_Dial"] = load(flDialXpm);
    pixmaps_["Fl_Roller"] = load(flRollerXpm);
    pixmaps_["Fl_Value_Input"] = load(flValueInputXpm);
    pixmaps_["Fl_Value_Output"] = load(flValueOutputXpm);
    pixmaps_["comment"] = load(flCommentXpm);

    pixmaps_["Fl_Spinner"] = load(flSpinnerXpm);
    pixmaps_["widget_class"] = load(flWidgetClassXpm);
    pixmaps_["data"] = load(flDataXpm);
    pixmaps_["Fl_Tree"] = load(flTreeXpm);
    pixmaps_["Fl_Table"] = load(flTableXpm);

    pixmaps_["Fl_Terminal"] = load(flSimpleTerminalXpm);
    pixmaps_["Fl_Input_Choice"] = load(flInputChoiceXpm);
    pixmaps_["CheckMenuItem"] = load(flCheckMenuitemXpm);
    pixmaps_["RadioMenuItem"] = load(flRadioMenuitemXpm);

    pixmaps_["Fl_Flex"] = load(flFlexXpm);
    pixmaps_["Fl_Grid"] = load(flGridXpm);

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
/// "fd_zoom", fd_zoom, 1)`) rather than living in this file's own XPM
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
