// D transliteration of FLTK's examples/tree-simple.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh tree-simple
import fl;
import std.stdio : stderr;

// Tree's callback
//    Invoked whenever an item's state changes.
void treeCallback(Widget w, Tree tree)
{
    auto item = tree.callbackItem();
    if (item is null)
        return;
    final switch (tree.callbackReason())
    {
    case CallbackReason.selected:
        string pathname = tree.itemPathname(item);
        stderr.writefln("treeCallback: Item selected='%s', Full pathname='%s'", item.label(), pathname);
        break;
    case CallbackReason.deselected:
        // stderr.writefln("treeCallback: Item '%s' deselected", item.label());
        break;
    case CallbackReason.opened:
        // stderr.writefln("treeCallback: Item '%s' opened", item.label());
        break;
    case CallbackReason.closed:
        // stderr.writefln("treeCallback: Item '%s' closed", item.label());
        break;
    // To enable this callback, use tree.itemReselectMode(selectableAlways);
    case CallbackReason.reselected:
        // stderr.writefln("treeCallback: Item '%s' reselected", item.label());
        break;
    case CallbackReason.unknown:
    case CallbackReason.dragged:
    case CallbackReason.cancelled:
    case CallbackReason.changed:
    case CallbackReason.gotFocus:
    case CallbackReason.lostFocus:
    case CallbackReason.released:
    case CallbackReason.enterKey:
    case CallbackReason.user:
        break;
    }
}

void main()
{
    scheme("gtk+");
    auto win = new DoubleWindow(250, 400, "Simple Tree");
    win.begin();
    {
        // Create the tree
        auto tree = new Tree(10, 10, win.w() - 20, win.h() - 20);
        tree.showroot(false); // don't show root of tree
        tree.callback((w) { treeCallback(w, tree); }); // setup a callback for the tree

        // Add some items
        tree.add("Flintstones/Fred");
        tree.add("Flintstones/Wilma");
        tree.add("Flintstones/Pebbles");
        tree.add("Simpsons/Homer");
        tree.add("Simpsons/Marge");
        tree.add("Simpsons/Bart");
        tree.add("Simpsons/Lisa");
        tree.add(`Pathnames/\/bin`); // front slashes
        tree.add(`Pathnames/\/usr\/sbin`);
        tree.add(`Pathnames/C:\\Program Files`); // backslashes
        tree.add(`Pathnames/C:\\Documents and Settings`);

        // Start with some items closed
        tree.close("Simpsons");
        tree.close("Pathnames");
    }
    win.end();
    win.resizable(win);
    win.show();
    fl.run();
}
