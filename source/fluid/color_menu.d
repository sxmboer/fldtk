/*
 * Ported from FLTK's own `colormenu[]` (`fluid/panels/
 * widget_panel_callbacks.cxx`): the 14-entry quick-pick color list
 * every "role color" swatch button in Fluid's own panels opens
 * (`widget_panel.fl`'s Style tab -- Color/Selection Color/Label Color/
 * Text Color -- and `settings_panel.fl`'s User tab -- 6 role colors).
 * Same story as `fluid.font_menu` (see that module's own doc comment
 * for the full design rationale): avoids
 * duplicating this as literal `MenuItem {}` children -- `settings_panel.fl`
 * alone would need 6 full 14-entry copies with a callback on *each item*
 * (`applyPresetColor(roleColor, presetValue, swatch)`), instead of
 * `widget_panel.fl`'s own, better-factored pattern (a shared,
 * if still per-file-private, `colorMenuNames`/`colorMenuValues`
 * arrays, one callback on the `Menu_Button` itself reading `.value()`
 * back). This module promotes that pattern to something both panels
 * share, and both panels use the *same* single-callback-on-the-
 * button shape.
 *
 * `colorMenuItems()` mirrors `fluid.font_menu.fontMenuItems()`'s own
 * shape (a function returning a fresh `MenuItem[]`, not a shared array
 * + `.dup` -- see that module's doc comment for why). Items carry no
 * callback of their own (unlike FLTK's `Fl_Menu_Item::argument()`-
 * based value, which FLTK's own shared `cb_Color_Choice()` reads
 * back) -- pair with `colorMenuValues` by index instead, matching this
 * project's own established "shared array + index into a parallel
 * value array" pattern (`alignPositionChoiceValues` et al.,
 * `widget_panel.fl`). `menuDivider` on "Inactive Color"/"White" matches
 * FLTK's own `FL_MENU_DIVIDER` placement exactly -- `widget_panel.fl`'s
 * own pre-existing `setup{}`-populated version had silently dropped
 * both dividers (`o.add(name, 0, null)`, flags always 0), fixed here
 * as this shared version replaces it.
 */
module fluid.color_menu;

import fl.menu_item : MenuItem, menuDivider;
import fl.enumerations : Color, foregroundColor, backgroundColor, background2Color,
    selectionColor, inactiveColor, black, white, gray0, dark3, dark2, dark1,
    light1, light2, light3;

MenuItem[] colorMenuItems()
{
    return [
        MenuItem("Foreground Color"),
        MenuItem("Background Color"),
        MenuItem("Background Color 2"),
        MenuItem("Selection Color"),
        MenuItem("Inactive Color", 0, null, menuDivider),
        MenuItem("Black"),
        MenuItem("White", 0, null, menuDivider),
        MenuItem("Gray 0"),
        MenuItem("Dark 3"),
        MenuItem("Dark 2"),
        MenuItem("Dark 1"),
        MenuItem("Light 1"),
        MenuItem("Light 2"),
        MenuItem("Light 3"),
        // `fl.menu_item`'s own item-array walk relies on a trailing
        // null-text sentinel to know where the array ends -- see
        // `fluid.font_menu.fontMenuItems()`'s own doc comment for the
        // real bug this fixes (found the same day, same root cause: the
        // first version of both functions omitted it).
        MenuItem(null),
    ];
}

immutable Color[14] colorMenuValues = [
    cast(Color) foregroundColor, cast(Color) backgroundColor, cast(Color) background2Color,
    cast(Color) selectionColor, cast(Color) inactiveColor, cast(Color) black, cast(Color) white,
    cast(Color) gray0, cast(Color) dark3, cast(Color) dark2, cast(Color) dark1,
    cast(Color) light1, cast(Color) light2, cast(Color) light3,
];

unittest
{
    // Regression test for the missing-sentinel case -- see
    // `fluid.font_menu.fontMenuItems()`'s own unittest for the full
    // reasoning (same shape, same root cause).
    import fl.menu_button : MenuButton;

    auto items = colorMenuItems();
    assert(items.length == 15); // 14 real colors + the trailing sentinel
    assert(items[$ - 1].text is null);

    auto m = new MenuButton(0, 0, 20, 20);
    m.menu(items);
    assert(m.size() == 15); // Menu_.size(): array length *including* the sentinel
    assert(colorMenuValues.length == 14);
}
