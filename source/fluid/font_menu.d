/*
 * Ported from FLTK's own `fontmenu[]` (`fluid/panels/
 * widget_panel_callbacks.cxx`): the 16 built-in FLTK font faces,
 * defined once and shared by every font-picking `Choice` in Fluid's own
 * panels, rather than duplicated as literal `MenuItem {}` children at
 * every call site (`widget_panel.fl`'s `styleLabelFont`/`styleTextFont`,
 * `settings_panel.fl`'s own font choices).
 *
 * Unlike FLTK's plain `extern Fl_Menu_Item fontmenu[];` +
 * `o->menu(fontmenu)` (a raw C array any translation unit in the same
 * binary can point at directly), this port's `fl.menu_.Menu_.menu(MenuItem[])`
 * takes a mutable slice -- and `MenuItem`'s own fields (`Callback
 * callback_`, `MenuItem* submenuItems_`, ...) make a single `immutable
 * MenuItem[]` constant uncastable back to mutable via a plain `.dup`
 * (`object.dup(const(T)[])`'s own template constraint,
 * `is(const(T) : T)`, doesn't hold for this struct). So `fontMenuItems`
 * is a function returning a fresh, independently-owned `MenuItem[]`
 * literal on every call, not a single shared array -- every caller
 * calls `fontMenuItems()` rather than `fontMenuItems.dup`.
 *
 * A `Choice`/`Menu_`-owning `WidgetNode` opts into this via the
 * `uses_font_menu` bare `.fl` flag (`WidgetNode.usesFontMenu`) instead
 * of literal `MenuItem {}` children -- `code_writer.d`'s codegen and
 * `instantiate.d`'s live-canvas apply both check it in place of the
 * usual `MenuItemNode`-children walk. Note this is a narrower
 * substitution than FLTK's own mechanism: FLTK's `fontmenu[]`
 * doesn't render any entry in the font it names either (confirmed by
 * reading `widget_panel_callbacks.cxx` -- no per-item `labelfont()` is
 * ever set), so this port doesn't either; a user report that assumed
 * otherwise was a misreading of an unrelated feature
 * (`fluid.node_browser`'s `classFont`, which bolds *class*-typed tree
 * rows, nothing to do with font pickers).
 *
 * Text for the last 3 entries deliberately preserves this project's own
 * pre-existing display text (`"Screen"`/`"Screen Bold"`/
 * `"ZapfDingbats"`, matching `fl.enumerations.Font`'s own symbolic
 * names -- `screen`/`screenBold`/`zapfDingbats`), not FLTK's actual
 * UI text at these 3 positions (`"Terminal"`/`"Terminal Bold"`/
 * `"Zapf Dingbats"`, with a space) -- confirmed identical across every
 * one of the 7 pre-existing duplicated copies this array replaces (both
 * panels), so a deliberate established convention here, not a stray
 * typo to silently correct while deduplicating; the mismatch itself is
 * out of scope for this pass.
 */
module fluid.font_menu;

import fl.menu_item : MenuItem;

MenuItem[] fontMenuItems()
{
    return [
        MenuItem("Helvetica"),
        MenuItem("Helvetica Bold"),
        MenuItem("Helvetica Italic"),
        MenuItem("Helvetica Bold Italic"),
        MenuItem("Courier"),
        MenuItem("Courier Bold"),
        MenuItem("Courier Italic"),
        MenuItem("Courier Bold Italic"),
        MenuItem("Times"),
        MenuItem("Times Bold"),
        MenuItem("Times Italic"),
        MenuItem("Times Bold Italic"),
        MenuItem("Symbol"),
        MenuItem("Screen"),
        MenuItem("Screen Bold"),
        MenuItem("ZapfDingbats"),
        // `fl.menu_item`'s own item-array walk relies on a trailing
        // null-text sentinel to know where the array ends
        // (`validateMenuArray()`'s own doc comment) -- without it,
        // `Menu_.menu(fontMenuItems())`
        // throws immediately at startup, in every caller, including
        // `widget_panel.d`'s own construction, so the whole editor
        // would fail to even launch. A test that only checks the
        // generated *text* shape or that codegen dispatched correctly,
        // without actually running `.menu()` against the real result,
        // wouldn't catch this.
        MenuItem(null),
    ];
}

unittest
{
    // Regression test for the missing-sentinel case this function's
    // own doc comment describes -- attaches the result to a
    // live `Menu_` via `.menu()` (which internally calls `fl.menu_item.
    // validateMenuArray()`), rather than only checking the array's shape.
    import fl.choice : Choice;

    auto items = fontMenuItems();
    assert(items.length == 17); // 16 real fonts + the trailing sentinel
    assert(items[$ - 1].text is null);

    auto c = new Choice(0, 0, 100, 20);
    c.menu(items); // throws on a missing sentinel -- this is the assertion
    assert(c.size() == 17); // Menu_.size(): array length *including* the sentinel
}
