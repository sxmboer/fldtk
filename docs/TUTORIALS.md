# Tutorials

Step-by-step introductions to making programs with fldtk and Fluid,
from the very first one on. Each builds on what the ones before it
show, so they are best read in order.

| | Tutorial | What it shows |
|---|---|---|
| 1 | [A first Fluid program](TUTORIAL01.md) | A window with two buttons that print a line: designing it in Fluid, and building and starting it with F5. |
| 2 | [A Fluid program as a dub project](TUTORIAL02.md) | A program as a dub project, ready to grow: having Fluid set the project up, what each file in it is for, callbacks that call a module of your own, and building it with dub in a terminal. |
| 3 | [Buttons, shortcuts and a group, on Windows](TUTORIAL03.md) | Several buttons with labels, keyboard shortcuts and callbacks, grouping them into one bar, making them radio buttons, and keeping and reading the chosen option; built on Windows. |
| 4 | [A bill splitter](TUTORIAL04.md) | Widgets for numbers: a Spinner, a Value Input, a Value Slider and Value Outputs, their ranges and steps, one callback shared by several widgets, when a callback runs, and a calculation in a function of your own. |

### Coming soon

These tutorials are planned but not written yet:

| | Tutorial | What it will show |
|---|---|---|
| 5 | Resizing | Making a window that stretches properly when it is resized: which widgets grow and which keep their size, and Flex and Grid as the easy way to arrange them. |
| 6 | Menus and files | A tiny notepad: a menu bar with shortcuts, a text editor, opening and saving files, and asking before quitting with unsaved changes. |
| 7 | Separating the GUI from your own code | The GUI as one part of a program: a window as a class designed in Fluid, started by a `launchGUI` function that the program's own `main()` calls. |
| 8 | Drawing and timers | A widget that draws itself, moved by a timer. |

All of them need a D compiler and dub, and a fldtk folder with Fluid
built in it; see [`BUILDING.md`](BUILDING.md).
