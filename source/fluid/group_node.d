/*
 * `Fl_Group` node -- a plain container, no properties beyond what
 * `WidgetNode` already reads (box/xywh/etc). First container type
 * needed beyond `Fl_Window` (radio.fl nests two of these for its
 * radio-button clusters). Ported from FLTK's `Group_Node`
 * (`fluid/nodes/Group_Node.h`/`.cxx`), structural shell only -- no
 * type-specific properties exist for a plain `Fl_Group`.
 */
module fluid.group_node;

import fluid.widget_node;

class GroupNode : WidgetNode
{
    override bool canHaveChildren() const { return true; }
}
