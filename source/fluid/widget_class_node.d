/*
 * `widget_class` node -- FLTK's mechanism for a `.fl` file to
 * define a real, reusable widget *subclass* whose top-level object IS
 * the window/group being designed, rather than a plain factory
 * function that builds one (every other `WindowNode` in this port).
 * Ported from FLTK's `Widget_Class_Node` (`fluid/nodes/
 * Window_Node.h`/`.cxx`).
 *
 * Structurally this is a `Window_Node` subclass in FLTK too --
 * `.fl` syntax is the ordinary widget shape (`widget_class Name {
 * properties } { children }`, parsed by this port's fully generic
 * `project_reader.d`/`project_writer.d` with zero changes needed
 * beyond this class itself and its one own property below), not
 * `Function`/`class`'s own distinct 2-brace-group shape. The
 * genuinely new piece is entirely in `code_writer.d`'s
 * `writeWidgetClassNode()`: instead of the usual "factory function
 * builds a `Window`/`Group` local variable" shape every other
 * `WindowNode` gets, a `WidgetClassNode` generates a real D `class
 * Name : BaseClass { this(...) { ... } }`, with every named child
 * widget becoming a class field (the same treatment
 * `fluid.class_node.ClassNode`'s own hand-authored classes already
 * get from `writeClassFields()`) rather than a module-level global.
 *
 * `wcRelative` mirrors FLTK's `wc_relative` exactly (0 = normal,
 * 1 = `position_relative` -- ignore the caller's X/Y, always place at
 * 0,0 -- 2 = `position_relative_rescale` -- also ignore W/H, always
 * use this node's own stored size). FLTK only lets this affect a
 * *non*-Window-shaped base class's own single constructor
 * (`write_code1()`'s `else` branch) -- ported the same way, see
 * `code_writer.d`'s own doc comment on the Window-vs-Group split for
 * why.
 *
 * The base class itself reuses `WidgetNode.classOverride` (the same
 * `class {Foo}` property override field every other widget already
 * has) rather than a new field -- matches FLTK's own `subclass()`
 * exactly (`Widget_Class_Node : Window_Node`, no separate base-class
 * field of its own), defaulting to `Group` (matching FLTK's own
 * `Fl_Group` default) when unset.
 */
module fluid.widget_class_node;

import fluid.window_node;
import fluid.project_reader : Reader;

class WidgetClassNode : WindowNode
{
    /// 0 = normal (constructor's own X/Y/W/H honored), 1 =
    /// `position_relative` (X/Y ignored, always 0,0), 2 =
    /// `position_relative_rescale` (X/Y *and* W/H ignored, always
    /// this node's own stored size) -- see this module's own doc
    /// comment.
    int wcRelative;

    override bool readProperty(Reader r, string name)
    {
        switch (name)
        {
        case "position_relative":
            wcRelative = 1;
            return true;
        case "position_relative_rescale":
            wcRelative = 2;
            return true;
        default:
            return super.readProperty(r, name);
        }
    }
}
