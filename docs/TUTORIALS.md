# Tutorials

[//]: # (This file is best viewed using a markdown reader https://md-reader.github.io/install)

Step-by-step introductions to making programs with fldtk and Fluid,
from the very first one on. Each builds on what the ones before it
show, so they are best read in order.

| | Tutorial | What it shows |
|---|---|---|
| 1 | [A first Fluid program](TUTORIAL01.md) | A window with two buttons that print a line: designing it in Fluid, and building and starting it with F5. |
| 2 | [A Fluid program as a dub project](TUTORIAL02.md) | A program as a dub project, ready to grow: having Fluid set the project up, what each file in it is for, callbacks that call a module of your own, and building it with dub in a terminal. |
| 3 | [Buttons, shortcuts and a group, on Windows](TUTORIAL03.md) | Several buttons with labels, keyboard shortcuts and callbacks, grouping them into one bar, making them radio buttons, and keeping and reading the chosen option, at last as a member of an enum of your own; built on Windows. |
| 4 | [A bill splitter, on Wayland](TUTORIAL04.md) | Widgets for numbers: a Spinner, a Value Input, a Value Slider and Value Outputs, their ranges and steps, one callback shared by several widgets, when a callback runs, and a calculation in a function of your own. |

### Coming soon

These tutorials are planned but not written yet:

| | Tutorial | What it will show |
|---|---|---|
| 5 | Resizing | Making a window that stretches properly when it is resized: which widgets grow and which keep their size, and Flex and Grid as the easy way to arrange them. |
| 6 | Menus and files | A tiny notepad: a menu bar with shortcuts, a text editor, opening and saving files, and asking before quitting with unsaved changes. |
| 7 | Separating the GUI from your own code | The GUI as one part of a program: a window as a class designed in Fluid, started by a `launchGUI` function that the program's own `main()` calls. |
| 8 | Drawing and timers | A widget that draws itself, moved by a timer. |

All of them need a D compiler and dub. Tutorial 1 shows how dub fetches
fldtk and starts Fluid; [`BUILDING.md`](BUILDING.md) covers building
fldtk from its own folder, wherever that is.

## Where fldtk and the tutorials are

The tutorials, and the finished designs they mention (`fourbuttons_1.fl`
and the like, in `docs/tutorial03` and the other `docs/tutorialNN`
folders), come with fldtk itself. Where they are on your computer
depends on how you got fldtk:

- **With `dub run fldtk:fluid`**, as Tutorial 1 does. As of fldtk
  v1.1.1, this works without downloading anything first: dub fetches
  fldtk into its own package folder, builds it there and starts Fluid.
  That folder is out of the way, and `dub list fldtk` shows where it
  is, for instance `/home/you/.dub/packages/fldtk/1.1.3/fldtk/` on
  Linux, or `C:\Users\you\AppData\Local\dub\packages\fldtk\1.1.3\fldtk\`
  on Windows.
- **As a clone of fldtk's git repository**, in a folder of your own
  choosing. Then that folder is fldtk's folder.

Either way, the easiest way to read the tutorials is from Fluid itself:
choose Help > fldtk README... and follow the link to the tutorials.
The links in them work there too, and clicking the name of a finished
design, such as [`fourbuttons_1.fl`](tutorial03/fourbuttons_1.fl), opens
it in Fluid, wherever fldtk is. Fluid asks first if the design you have
open has unsaved changes. To experiment with a finished design, first
save it in a folder of your own with File > Save As...: F5 saves the
design before building it, so working on the original would change the
tutorial's own file. The designs are in the `docs` folder next to
the tutorials, so `docs/tutorial03/fourbuttons_1.fl` for Tutorial 3.
