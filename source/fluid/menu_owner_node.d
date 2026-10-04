/*
 * A widget that owns a menu (`Fl_Menu_Button`, `Fl_Choice`, ...) --
 * identical to `WidgetNode` except `canHaveChildren()` is true, so the
 * reader actually parses its nested `MenuItem { ... }` children (a
 * plain `WidgetNode`'s `canHaveChildren()` is false, which would make
 * `Reader.parseNode()` skip the trailing children block entirely).
 */
module fluid.menu_owner_node;

import fluid.widget_node;

class MenuOwnerNode : WidgetNode
{
    override bool canHaveChildren() const { return true; }
}
