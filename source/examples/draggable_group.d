// D transliteration of FLTK's examples/draggable-group.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh draggable-group
import fl;
import std.format : format;

/**
 * Class with draggable children, derived from FlGroup.
 *
 * Use this class if you want the user to be able to drag the children
 * of a group inside the borders of the group. DraggableGroup widgets
 * can be nested, but only direct children of the DraggableGroup widget
 * can be dragged.
 */
class DraggableGroup : FlGroup
{
protected:
    int xoff, yoff;     // start offsets while dragging
    int dragIndex;      // index of dragged child
    Widget dragWidget;  // dragged child widget

public:
    this(int X, int Y, int W, int H, string L = null)
    {
        super(X, Y, W, H, L);
        xoff = 0;
        yoff = 0;
        dragIndex = 0;
        dragWidget = null;
        box(Boxtype.upBox);
    }

    /// Raise the dragged widget to the top (last child) of its group.
    void topLevel(Widget q)
    {
        dragIndex = find(q); // save the widget's current index
        add(q);              // raise to top (make it the last child)
    }

    /// Handle FL_PUSH, FL_DRAG, and FL_RELEASE events.
    override int handle(Event e)
    {
        switch (e)
        {
        case Event.push:
            if (fl.eventButton() == rightMouse)
            {
                if (fl.belowmouse().parent() is this)
                {
                    dragWidget = fl.belowmouse();

                    // save pointer offsets relative to dragWidget's x/y position
                    xoff = fl.eventX() - dragWidget.x();
                    yoff = fl.eventY() - dragWidget.y();

                    topLevel(dragWidget); // raise to top for visible feedback
                    redraw();
                    return 1;
                }
            }
            break;

        case Event.drag:
            if (!dragWidget)
                break;

            int nX = fl.eventX() - xoff; // new x coordinate
            int nY = fl.eventY() - yoff; // new y coordinate

            int bbx = fl.boxDx(box()); // left and right border width
            int bby = fl.boxDy(box()); // top and bottom border width

            // keep the widget inside its parent's borders

            if (nX < x() + bbx)
                nX = x() + bbx;
            else if (nX + dragWidget.w() > x() + w() - bbx)
                nX = x() + w() - dragWidget.w() - bbx;

            if (nY < y() + bby)
                nY = y() + bby;
            else if (nY + dragWidget.h() > y() + h() - bby)
                nY = y() + h() - dragWidget.h() - bby;

            dragWidget.position(nX, nY); // set the new position
            redraw();
            return 1;

        case Event.release:
            if (dragWidget && fl.eventButton() == rightMouse)
            {
                // Optional: restore the original widget order in the group.
                insert(dragWidget, dragIndex);

                initSizes(); // save widget positions for later resizing
                dragWidget = null;
                redraw();
                if (parent())
                    parent().redraw();
                return 1;
            }
            break;

        default:
            break;
        }

        return super.handle(e);
    }
}

// tooltips:

immutable string ttDrag = "Drag this DraggableGroup and/or its child groups and squares. "
    ~ "Use the right mouse button (MB3) to drag objects.";
immutable string ttGroup = "You can drag this Group, but not its children (squares).";
immutable string ttButton = "You can drag this button with the right mouse button "
    ~ "and you can click it with the left mouse button.";

void main()
{
    auto win = new DoubleWindow(500, 500, "Drag children within their parent group");

    auto area = new DraggableGroup(0, 0, 500, 400, "Use the right mouse button (MB3)\nto drag objects");
    area.alignment(alignInside);
    area.tooltip(ttDrag);

    // draggable group inside draggable area
    auto dobj = new DraggableGroup(5, 5, 140, 140, "DraggableGroup");
    dobj.alignment(alignInside);
    auto b1 = new Box(25, 25, 20, 20);
    b1.color(red);
    b1.box(Boxtype.flatBox);
    auto b2 = new Box(105, 105, 20, 20);
    b2.color(green);
    b2.box(Boxtype.flatBox);
    dobj.end();
    dobj.tooltip(ttDrag);

    // regular group inside draggable area
    auto dobj2 = new FlGroup(5, 280, 110, 110, "Group");
    dobj2.box(Boxtype.downBox);
    dobj2.alignment(alignInside);
    auto b3 = new Box(15, 290, 20, 20);
    b3.color(blue);
    b3.box(Boxtype.flatBox);
    auto b4 = new Box(85, 360, 20, 20);
    b4.color(yellow);
    b4.box(Boxtype.flatBox);
    dobj2.end();
    dobj2.tooltip(ttGroup);

    // draggable group inside draggable area
    auto dobj3 = new DraggableGroup(245, 5, 150, 150, "DraggableGroup");
    dobj3.alignment(alignInside);
    dobj3.tooltip(ttDrag);

    // nested draggable group
    auto dobj4 = new DraggableGroup(250, 10, 50, 50);
    auto b5 = new Box(255, 15, 15, 15);
    b5.color(black);
    b5.box(Boxtype.flatBox);
    auto b6 = new Box(275, 30, 15, 15);
    b6.color(white);
    b6.box(Boxtype.flatBox);
    dobj4.end();
    dobj4.tooltip(ttDrag);

    dobj3.end();

    auto button1 = new Button(200, 350, 180, 40, "Button inside DraggableGroup");
    button1.alignment(alignInside | alignWrap);
    button1.tooltip(ttButton);

    area.end();

    auto button2 = new Button(200, 410, 180, 40, "Button outside DraggableGroup");
    button2.alignment(alignInside | alignWrap);
    button2.tooltip("This is a normal button and can't be dragged.");

    auto status = new Box(0, 460, win.w(), 40, "Messages ...");
    status.box(Boxtype.downBox);

    // clear status message box after timeout
    void clearStatus()
    {
        status.label("");
        status.redraw();
    }

    // button callback: display status message for two seconds
    void buttonCb(Widget w)
    {
        status.label(format("button_cb: '%s'.\n", w.label()));
        status.redraw();
        fl.removeTimeout(&clearStatus); // remove any pending timeout
        fl.addTimeout(2.0, &clearStatus);
    }

    button1.callback(&buttonCb);
    button2.callback(&buttonCb);

    win.end();
    win.resizable(win);
    win.show();

    fl.run();
}
