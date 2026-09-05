This project is about 99% done. The library and fluid run stable. 
The first commit will have the fully functional library with fluid integrated in the dub package.
It will support Linux/X11. Linux/Wayland and Windows drivers will hopefully follow soon.

Sneak peak:
fldtk has the exact look and feel of FLTK. Everything is fully implemented in D syntax. Here is a simple example program.
``` D
import fl;
import std;

void main()
{
  auto win = new Window(100, 100, 400, 300, "fldtk smoke test: Button");
  auto btn = new Button(20, 20, 360, 260, "Click!"); // auto-parents into win (Group.current())
  win.end(); // not really needed here
  win.show();

  fl.run();
}
```
which will produce a window with a clickable button.

<img width="412" height="333" alt="button" src="https://github.com/user-attachments/assets/c1d54510-d5fb-4408-87cd-b63c48e08104" />

