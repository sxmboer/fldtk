/*
 * A single `MenuItem { ... }` entry nested inside a menu-owning widget
 * (e.g. `Fl_Menu_Button`/`Fl_Choice`). Structurally an ordinary
 * `WidgetNode` (same `label`/`callback`/etc. properties, `xywh` present
 * but ignored -- FLTK's own generated `Fl_Menu_Item` struct has no
 * position field either) -- this subclass exists purely so `code_writer.d`
 * can `cast(MenuItemNode)` to tell a menu item apart from a real
 * widget child when deciding how to emit a node's children (a
 * `MenuItem[]` array literal + `.menu(arr)` call, not a normal widget
 * subtree -- see `code_writer.d`'s `writeMenuOwnerNode()`, grounded against
 * the real generated `menu_menu[]` array in
 * FLTK's `build/test/inactive.cxx`).
 */
module fluid.menu_item_node;

import fluid.widget_node;
import fluid.project_reader : Reader;

class MenuItemNode : WidgetNode
{
    // FLTK: `Menu_Item_Node::headline_` (`Menu_Node.h`) -- a bare
    // flag, menu-item-only (unlike `hotspotFlag`, which lives on
    // `WidgetNode` itself since it's dual-purpose across every widget
    // kind). Marks this item as a non-selectable section heading
    // (`FL_MENU_HEADLINE`), drawn via `fl.menu_item.MenuItem.flags`'s
    // `menuHeadline` bit -- see `code_writer.d`'s `menuItemFlags()`.
    bool headline_;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "headline":
            headline_ = true;
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}

/// FLTK: `Submenu_Node` (`Menu_Node.h`/`.cxx`) -- the one menu-item
/// kind that's a real container: a submenu's own nested items are
/// ordinary `MenuItem { ... }` (or further-nested `Submenu { ... }`)
/// children of *this* node, not of the menu-owning widget directly.
/// `canHaveChildren()` is the only behavioral difference from a plain
/// `MenuItemNode` (matching `Node.canHaveChildren()`'s own doc comment:
/// `Reader.parseNode()` skips a node's trailing children block entirely
/// unless this returns `true` -- the same reason `fluid.menu_owner_node.
/// MenuOwnerNode` exists as its own trivial subclass of `WidgetNode`).
///
/// `CheckMenuItem`/`RadioMenuItem` deliberately do NOT get their own
/// subclasses the way `Submenu` does here: FLTK only splits those
/// into `Checkbox_Menu_Item_Node`/`Radio_Menu_Item_Node` because C++
/// factory dispatch needs a distinct concrete type per registered
/// `type_name()` (`Menu_Node.cxx`'s `Checkbox_Menu_Item_Node::make()`/
/// `Radio_Menu_Item_Node::make()` both just forward into the *same*
/// `Menu_Item_Node::make(int flags, Strategy)`, baking `FL_MENU_TOGGLE`/
/// `FL_MENU_RADIO` into the new item's `Fl_Button`'s own `type()`).
/// `fluid.factory`'s registry is a plain string-keyed constructor map,
/// and `Node.typeName` (set generically by both `project_reader.d`'s
/// parser and `gui_main.d`'s `addNode()`) already carries exactly that
/// same "which `.fl` keyword created this" signal round-trip-safe --
/// `code_writer.d`'s and `instantiate.d`'s own `menuItemFlags()` read
/// `mi.typeName` directly (`"CheckMenuItem"`/`"RadioMenuItem"`) instead
/// of needing a second D class purely to be `cast()`-distinguishable,
/// with nothing lost: neither kind has ANY other behavioral difference
/// from a plain `MenuItemNode` (same properties, same `canHaveChildren()
/// == false`).
///
/// Changing an existing item's kind (FLTK's `menu_item_type_menu`) goes
/// through `fluid.subtypes`' `SubtypeStorage.menuItemKind`, which rewrites
/// `typeName`; the Widget Properties panel hides the shortcut field for a
/// submenu, as FLTK's `Submenu_Node::is_button() == 0` does.
class SubmenuNode : MenuItemNode
{
    override bool canHaveChildren() const { return true; }
}
