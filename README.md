This project is about 90% done. I am currently implementing the D version of fluid -- support full D syntax, new GUI interface for D, drop need for .h files, etc.
The first commit will have the fully functional library with fluid integrated in the dub package.

Sneak peak:
Everything is fully implemented in D syntax. Here is a simple example program.
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

<img width="400" height="300" alt="button" src="https://github.com/user-attachments/assets/920e1aea-c5a5-487e-8832-5206cd0e92f9" />
