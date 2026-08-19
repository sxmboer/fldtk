This project is about 90% done. I am currently implementing the D version of fluid -- support full D syntax, new GUI interface for D, drop need for .h files, etc.
The first commit will have the fully functional library with fluid integrated in the dub package.

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

