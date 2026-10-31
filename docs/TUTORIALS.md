# Tutorials

Step-by-step introductions to making programs with fldtk and Fluid,
from the very first one on. Each builds on what the ones before it
show, so they are best read in order.

| | Tutorial | What it shows |
|---|---|---|
| 1 | [A first Fluid program](TUTORIAL01.md) | A window with a button that prints "Hello, World!": designing it in Fluid, and building it in the fldtk folder with dub or with make. |
| 2 | [A Fluid program as a dub project](TUTORIAL02.md) | A program in a project folder of its own: setting up a dub project that depends on fldtk, and having dub run Fluid on every build. |
| 3 | [Buttons, shortcuts and a group, on Windows](TUTORIAL03.md) | Several buttons with labels, keyboard shortcuts and callbacks, grouping them into one bar, making them radio buttons, and keeping and reading the chosen option; built on Windows. |

### Coming soon

These tutorials are planned but not written yet:

| | Tutorial | What it will show |
|---|---|---|
| 4 | Typing and showing values | A small converter: input and output fields, turning typed text into numbers and back, handling input that is not a number, and when a field's callback runs. |
| 5 | Resizing | Making a window that stretches properly when it is resized: which widgets grow and which keep their size, and Flex and Grid as the easy way to arrange them. |
| 6 | Menus and files | A tiny notepad: a menu bar with shortcuts, a text editor, opening and saving files, and asking before quitting with unsaved changes. |
| 7 | Separating the GUI from your own code | A window as a class designed in Fluid, with the program's own logic in a plain D module that the callbacks call. |
| 8 | Drawing and timers | A widget that draws itself, moved by a timer. |

All of them need a D compiler and dub, and a fldtk folder with Fluid
built in it; see [`BUILDING.md`](BUILDING.md).
