# fldtk Technical Reference

[//]: # (This file is best viewed using a markdown reader https://md-reader.github.io/install)

This is the reference for programming with fldtk: what the toolkit
consists of, how a program is put together, every widget of Fluid's
widget bin with its member functions and the values its properties
take, and the rest of the library a program needs. The
[tutorials](TUTORIALS.md) teach fldtk step by step, the
[demo programs](../source/test/README.md) show it working, and
[BUILDING.md](BUILDING.md) explains building.

The member tables list the public functions each class declares
itself, with the first sentence of their documentation from the source.
A class also has the members of the classes above it; each section says
which those are.

Contents:

1. [Introduction](#1-introduction)
2. [Every widget](#2-every-widget)
3. [Code](#3-code)
4. [Groups](#4-groups)
5. [Buttons](#5-buttons)
6. [Valuators](#6-valuators)
7. [Text](#7-text)
8. [Menus](#8-menus)
9. [Browsers](#9-browsers)
10. [Misc](#10-misc)
11. [Beyond widgets](#11-beyond-widgets)

## 1. Introduction

fldtk (Full-D-toolkit) is a GUI toolkit written in D. A program built
with it runs from the same source on Linux (X11 and Wayland) and
Windows, and needs no libraries beyond what the system provides. It
comes in four parts.

| Part | What it is | Build and start it |
|---|---|---|
| The library | The widgets, drawing, images, dialogs and events: `import fl;` | `dub build` (makes `libfldtk.so`, `fldtk.lib` on Windows) |
| Fluid | The designer: draw a window with the mouse, set the widgets' properties, and Fluid writes the D code. F5 builds and runs the program. | `dub run fldtk:fluid`, or `dub build :fluid` in the fldtk folder |
| fldtk-options | The settings every fldtk program reads when it starts: scheme, zoom, tooltips, visible keyboard focus, dragging text, and on Linux Wayland or X11 and Xlib or Cairo drawing; for you or for every user of the computer. It also works from the command line (`fldtk-options -h`). | `dub build fldtk:options` |
| The demo | One window that starts the demo programs: one for nearly every widget and feature, with their source in `source/test/` and `source/examples/` | `dub run fldtk:demo` |

### A first program

```D
import fl;

void main()
{
    auto win = new Window(300, 180, "Hello");
    auto button = new Button(100, 70, 100, 40, "Click me");
    button.callback((w) { button.label("Thanks!"); });
    win.end();
    win.show();
    fl.run();
}
```

A dub project gets fldtk with `dub add fldtk`; `dub run` then builds
and starts the program.

### How a program fits together

**The widget tree.** Every widget sits in a group, and a window is a
group. A new widget goes into the *current group*: creating a window or
group makes it the current one, and its `end()` makes its parent the
current one again. So the widgets created between `new Window(...)` and
`win.end()` are the window's.

**Coordinates.** Positions and sizes are whole pixels: `x`, `y` for the
top left corner, then the width `w` and height `h`. A widget's position
is counted from the top left corner of its window, not of its group. A
window's own `x`, `y` are on the screen.

**The event loop.** `win.show()` puts the window on the screen and
`fl.run()` handles events (mouse, keyboard, timers, redrawing) until the
last window closes.

**Callbacks.** A widget calls its callback, a delegate taking the
widget, when the user does something with it: clicks a button, moves a
slider, presses Enter in an input field. When exactly is the widget's
`when()` setting (see [When the callback is called](#when-the-callback-is-called)).

**Labels and looks.** Most widgets show a label; `alignment()` places
it outside or inside the widget. Their looks are their box type
(`box()`), colours (`color()`, `selectionColor()`), and the label's font,
size and colour. The scheme (set in fldtk-options, or by the program)
gives all box types a common style.

**Drawing happens later.** Changing a property redraws the widget the
next time the program waits for events, not at once. A widget that
draws itself calls `redraw()` when what it shows changes.

**Resizing.** When a window is resized, its `resizable()` widget grows
and shrinks with it and the others keep their size; inside a group, the
same goes for the group's `resizable()`. Without a resizable widget, the
window can't be resized.

### Reading this reference

Sections 3 to 10 follow Fluid's widget bin, group by group, in the
bin's order. Section 3 is the code a design holds besides its widgets.
From section 4 on, each widget has its bin icon, a picture, what it is
for, how to make one in code, its member functions, and the constants
its properties take. Section 2 holds what every widget has in common,
and section 11 the parts of the library that aren't widgets.

## 2. Every widget

Every widget is a `Widget`: these members belong to all of them. A
property is a pair of functions with one name: `label()` gives the
label and `label("Name")` sets it.

@members Widget

### Box types

`box()` sets how a widget's background is drawn. The `...Frame` types
draw only the border. The look of most types follows the scheme.

@enum Boxtype

### Label types

`labeltype()` sets how a label is drawn.

@enum Labeltype

### Alignment

`alignment()` places the label, as a combination of these with `|`:
`alignTop | alignLeft` puts it above the widget, at its left. With
`alignInside` it goes inside the widget.

@constants fl.enumerations align

### When the callback is called

`when()` sets when a widget calls its callback, as a combination of
these with `|`.

@constants fl.enumerations When

### Fonts

`labelfont()` and `textfont()` take a font. `Font` values beyond these
are added with `fl.draw.setFont()`.

@constants fl.enumerations Font

### Colours

Properties such as `color()`, `labelcolor()` and `selectionColor()`
take a `Color`: one of these, an index into the colour map, or
`rgbColor(r, g, b)`.

@constants fl.enumerations Color

### Why a callback was called

`fl.core.callbackReason()` says, inside a callback, why it was called.

@enum CallbackReason

## 3. Code

Besides widgets, a design holds code: the first group of Fluid's widget
bin. Fluid writes each node's code into the generated `.d` file where the
node stands in the widget tree, top to bottom, so the tree is also an
outline of the file. Every one of these nodes has a Comment field on its
properties page, written as a comment above its code.

Where a node stands decides what its code can be:

| Place in the tree | What goes there |
|---|---|
| At the top, not inside anything (the file itself, D's *module scope*) | imports, variables and types the whole file shares, functions, classes |
| Directly in a Class | fields and methods |
| In a Function, or among a window's widgets | statements, run one after the other when the function runs |

### ![](../source/fluid/pixmaps_svg/flFunction.svg) Function

A function. With its Function field left blank, it is the program's
`main()`: Fluid writes `void main(string[] args)`, builds the widgets
inside it, shows its windows and starts `fl.run()`. A design has one
such Function.

With a name and parameters, such as `makeWindow()` or `buttonCB(Button
b)`, it is an ordinary function that the program calls itself; inside a
Class it is a method, `this(...)` a constructor and `~this()` the
destructor. Its children are its body: Code nodes, Conditional nodes and
widgets, in order.

- **Return Type**: blank in a function that builds widgets gives the
  type of its first widget, and the function returns that widget; so a
  `makeWindow()` holding a window returns the window, and the program
  shows it with `makeWindow().show();`. Blank otherwise, and in a
  method, is `void`.
- **Visibility**: `static` makes a top-level function `private` to the
  generated file; `global` and `local` leave it public. In a Class, the
  choice is `private`, `public` or `protected`.
- **declare "C"**: writes the function as `extern (C)`, for a function
  that C code calls. It has no effect on a method.

Several widgets can share one callback: write it as a named Function and
call it from each widget's callback with the widget, `buttonCB(o);`.

### ![](../source/fluid/pixmaps_svg/flClass.svg) Class

A D class. **Class Name** is its name, **Base Class** what it is based
on (often a widget type, such as `Window` or `Group`; blank for none),
and **Attribute** words written before `class`, such as `final` or
`abstract`.

Its children make up the class, in order: a Code node is a field, a
Function a method, a Conditional fields or methods under a condition,
and a Class a class inside it. A named widget that one of its methods
builds becomes a field, so each object of the class has its own.

A widget of your own, `class MyButton : Button` with methods that change
how it behaves, is used by placing a Button in a window and typing
`MyButton` in its `class` property. A group of your own builds its
widgets in its constructor:

```
class Counter : Group
    Function this(int x, int y, int w, int h, string label = null)
        Code     super(x, y, w, h, label);
        Button   minus
        Output   count
        Button   plus
        Code     end();
```

A class that has nothing to do with widgets works too, but belongs in a
`.d` module of the program's own.

### ![](../source/fluid/pixmaps_svg/flCode.svg) Code

D code, written as it is where the node stands. What it can hold depends
on the place:

| Place | Example |
|---|---|
| At the top | `import std.stdio;`, `int clicks;`, `enum Size { small, medium, large }` |
| In a Class | `int count;` |
| In a Function, among widgets | `writeln("ready");`, `clicks++;` |

A Code node can also put a file into the program when it is compiled,
with D's `import("file")`: `enum help = import("help.md");` for text,
`immutable ubyte[] logo = cast(immutable ubyte[])
import("pictures/logo.png");` for anything else. The file is named by
its path from the folder of the `.fl` file and must be inside that
folder; Fluid tells the compiler to look there.

**Edit Externally...** opens the code in your own text editor, the one
named in Edit > Settings..., General, External Editor, once Use for Code
Nodes is checked there. Each time you save in that editor, the node
takes the new text.

### ![](../source/fluid/pixmaps_svg/flCodeBlock.svg) Conditional

Code and widgets that are only there when a condition holds. The
**Condition** is written as given, and the node's children inside `{
... }` after it. An `else` is a Conditional node of its own, placed
directly after the `if` (or `static if`, `version`, `debug`) node it
belongs to. Fluid doesn't check the condition or where it stands; the
compiler reports one that doesn't fit.

| Condition | Example | Works | Decided |
|---|---|---|---|
| `if (...)` | `if (args.length > 1)` | in a Function | when the program runs |
| `else` | `else` | after an `if`, `static if`, `version` or `debug` node | as that node |
| `static if (...)` | `static if (size_t.sizeof == 8)` | everywhere | when the program is compiled |
| `version (...)` | `version (Windows)` | everywhere | when the program is compiled |
| `debug` | `debug` | everywhere | when the program is compiled |

- `version` names the system or the compiler: `Windows`, `linux`,
  `Posix`, `X86_64`, `DigitalMars` (dmd), `LDC`, `GNU` (gdc).
  `version (none)` switches code off without deleting it, and `version
  (unittest)` keeps it for `dub test` only.
- `debug` code is in the everyday build, `dub build` and Fluid's Run, and
  left out of `dub build -b release`: a place for checks and messages
  the finished program doesn't need.
- `static if` tests anything the compiler knows, such as a type's size or
  whether a module is there.

To put existing nodes under a condition, select them in the tree (two
or more, with Ctrl-click) and add a Conditional, from the New menu or
the widget bin: it takes the place of the first selected node, and the
selected nodes move into it, in their order, wherever they were. Widgets
can be wrapped among the widgets of their own window, not in a Flex or
Grid. When the nodes can't go into a Conditional there, it is added as
usual instead. A Function or a Class wraps nodes the same way. **Unwrap**,
in the tree's right-click menu, does the reverse: the selected
Conditional node's children move up to its place, and it is removed.
Each is one step for Undo.

### ![](../source/fluid/pixmaps_svg/flComment.svg) Comment

A note in the widget tree, also written as a comment in the generated
code where it stands. With **output to source file** unchecked, it stays
in the `.fl` file only. **Predefined** keeps comment texts you use often,
such as a licence: Edit, Add current comment... saves the text, and it
can then be chosen in any project. **Import...** reads the text from a
file.

## 4. Groups

A group holds other widgets: it moves them, draws them, and hands them
events. Each group below is an `FlGroup`, with these members as well as
those of `Widget`.

To go through a group's widgets, use `widgets`; `allWidgets` also
takes the widgets inside the groups inside it. Both are arrays, so
Phobos works on them:

```D
foreach (w; group.widgets)
    w.deactivate();
auto edited = window.allWidgets.filter!(w => w.changed).array;
```

@members FlGroup

### ![](../source/fluid/pixmaps_svg/flWindow.svg) Window

![Window](widgets/window.png)

A window on the screen, holding the program's widgets. Fluid makes a
`DoubleWindow`, which draws into a hidden buffer first and so doesn't
flicker; it has the same members. A window created inside another
window's group is a window inside that window.

@constructor Window

@members Window

### ![](../source/fluid/pixmaps_svg/flGroup.svg) Group

![Group](widgets/group.png)

`FlGroup` itself: a container that keeps its children where they were
put. With a box type (such as `Boxtype.engravedFrame`) and a label it
frames related widgets.

@constructor FlGroup

### ![](../source/fluid/pixmaps_svg/flPack.svg) Pack

![Pack](widgets/pack.png)

Lines its children up one after the other, in a row or a column,
spaced `spacing()` apart; each keeps its own width (in a row) or height
(in a column).

@constructor Pack

@members Pack

`type()` values:

@constants fl.pack

### ![](../source/fluid/pixmaps_svg/flTabs.svg) Tabs

![Tabs](widgets/tabs.png)

Shows one child at a time, with a tab for each child's label to pick
it. Each child is a group that fills the area below the tabs.

@constructor Tabs

@members Tabs

What happens when the tabs don't fit (`handleOverflow()`):

@constants fl.tabs overflow

### ![](../source/fluid/pixmaps_svg/flScroll.svg) Scroll

![Scroll](widgets/scroll.png)

Shows part of an area larger than itself, with scrollbars to move
around in it. The children may lie anywhere; the scrollbars cover them
all.

@constructor Scroll

@members Scroll

`type()` values, which scrollbars show:

@constants fl.scroll

### ![](../source/fluid/pixmaps_svg/flFlex.svg) Flex

![Flex](widgets/flex.png)

Lays its children out in a row or a column and shares the space between
them, `gap()` apart; `fixed()` gives a child a size of its own. Resizing
the Flex lays them out again.

@constructor Flex

@members Flex

Directions:

@constants fl.flex

### ![](../source/fluid/pixmaps_svg/flTile.svg) Tile

![Tile](widgets/tile.png)

Children side by side and above each other, filling the Tile, with
borders the user drags to make one larger and its neighbours smaller.

@constructor Tile

@members Tile

### ![](../source/fluid/pixmaps_svg/flWizard.svg) Wizard

![Wizard](widgets/wizard.png)

Shows one child at a time, without tabs: the program goes to the next
or previous one with `next()` and `prev()`, as in a dialog that asks
its questions in steps.

@constructor Wizard

@members Wizard

### ![](../source/fluid/pixmaps_svg/flGrid.svg) Grid

![Grid](widgets/grid.png)

Lays its children out in rows and columns. `layout(rows, cols)` sets
the size of the grid, `widget(w, row, col)` puts a child in a cell (also
over several rows or columns), and the cells' sizes follow the Grid's.

@constructor Grid

@members Grid

How a child sits in its cell:

@constants fl.grid

## 5. Buttons

Each button is a `Button`, with these members as well as those of
`Widget`. `value()` is 1 when the button is on.

@members Button

`type()` values: a normal button calls back when clicked, a toggle
button stays on or off, and of the radio buttons in one group only one
is on.

@constants fl.button

To find out which radio button of a group is on, name the options in an
enum and ask the group: the first radio button stands for the enum's
first member, the second for its second, and so on. "First" means first
in the group, as in Fluid's widget tree, not where the button is in the
window: after moving buttons around in the tree with Earlier and Later
(F2, F3), put them back in the order of the enum. `selectRadioButton()`
sets the choice from the program.

```D
enum Size { small, medium, large }

Size s = sizes.selectedRadioButton!Size;
sizes.selectRadioButton(Size.large);
```

Without an enum, `selectedRadioButton` gives the radio button that is
down itself, or `null` when none is, so its label or any other property
can be read:

```D
message(format("%s is selected", sizes.selectedRadioButton.label));
```

For buttons that are on or off each by themselves, such as check
buttons, `selectedButtons` gives every button of the group that is on:

```D
foreach (b; options.selectedButtons)
    writeln(b.label, " is on");
```

### ![](../source/fluid/pixmaps_svg/flButton.svg) Button

![Button](widgets/button.png)

A push button.

@constructor Button

### ![](../source/fluid/pixmaps_svg/flReturnButton.svg) Return Button

![Return Button](widgets/return_button.png)

A button that the Enter key also presses, with a symbol saying so: the
default button of a dialog.

@constructor ReturnButton

### ![](../source/fluid/pixmaps_svg/flLightButton.svg) Light Button

![Light Button](widgets/light_button.png)

A button with a light that shows whether it is on. Clicking switches it.

@constructor LightButton

@members LightButton

### ![](../source/fluid/pixmaps_svg/flRepeatButton.svg) Repeat Button

![Repeat Button](widgets/repeat_button.png)

A button that calls back again and again while it is held down.

@constructor RepeatButton

@members RepeatButton

### ![](../source/fluid/pixmaps_svg/flCheckButton.svg) Check Button

![Check Button](widgets/check_button.png)

A check box with a label: on or off.

@constructor CheckButton

### ![](../source/fluid/pixmaps_svg/flRoundButton.svg) Round Button

![Round Button](widgets/round_button.png)

A round indicator with a label. As a radio button, it picks one option
of several.

@constructor RoundButton

## 6. Valuators

A valuator holds a number between a minimum and a maximum, in steps.
Each is a `Valuator`, with these members as well as those of `Widget`.
The mouse wheel changes any of them: 10 steps a notch, 1 with Shift,
100 with Ctrl.

@members Valuator

Orientation, for the valuators that have one:

@constants fl.valuator

### ![](../source/fluid/pixmaps_svg/flSlider.svg) Slider

![Slider](widgets/slider.png)

A knob the user slides along a track.

@constructor Slider

@members Slider

`type()` values and tick marks:

@constants fl.slider

### ![](../source/fluid/pixmaps_svg/flScrollBar.svg) Scroll Bar

![Scroll Bar](widgets/scroll_bar.png)

A slider with arrows at its ends, whose knob shows how much of
something is in view. A `Slider`, with these members as well.

@constructor Scrollbar

@members Scrollbar

### ![](../source/fluid/pixmaps_svg/flValueSlider.svg) Value Slider

![Value Slider](widgets/value_slider.png)

A slider that also shows its value as a number. A `Slider`, with these
members as well.

@constructor ValueSlider

@members ValueSlider

### ![](../source/fluid/pixmaps_svg/flValueOutput.svg) Value Output

![Value Output](widgets/value_output.png)

Shows a number, which the user can't change.

@constructor ValueOutput

@members ValueOutput

### ![](../source/fluid/pixmaps_svg/flAdjuster.svg) Adjuster

![Adjuster](widgets/adjuster.png)

Three small buttons that change the value by dragging over them, each
by a different amount: fine, medium and coarse.

@constructor Adjuster

@members Adjuster

### ![](../source/fluid/pixmaps_svg/flCounter.svg) Counter

![Counter](widgets/counter.png)

A number between arrow buttons that step it down and up; the outer
arrows take larger steps (`lstep()`).

@constructor Counter

@members Counter

`type()` values:

@constants fl.counter

### ![](../source/fluid/pixmaps_svg/flDial.svg) Dial

![Dial](widgets/dial.png)

A round knob the user turns.

@constructor Dial

@members Dial

`type()` values:

@constants fl.dial

### ![](../source/fluid/pixmaps_svg/flRoller.svg) Roller

![Roller](widgets/roller.png)

A wheel the user rolls with the mouse, for a value without fixed
ends in sight.

@constructor Roller

@members Roller

### ![](../source/fluid/pixmaps_svg/flSpinner.svg) Spinner

![Spinner](widgets/spinner.png)

A number field with up and down arrows, for whole numbers or with
decimals.

@constructor Spinner

@members Spinner

### ![](../source/fluid/pixmaps_svg/flValueInput.svg) Value Input

![Value Input](widgets/value_input.png)

A number field the user types in, or drags over to change.

@constructor ValueInput

@members ValueInput

## 7. Text

The one-line text widgets (Input, Output, File Input) are each an
`Input_`, with these members as well as those of `Widget`.

@members Input_

### ![](../source/fluid/pixmaps_svg/flInput.svg) Input

![Input](widgets/input.png)

A one-line field for text the user types. `IntInput`, `FloatInput`,
`SecretInput` and `MultilineInput` are inputs for whole numbers,
numbers, passwords and several lines.

@constructor Input

@members Input

### ![](../source/fluid/pixmaps_svg/flOutput.svg) Output

![Output](widgets/output.png)

Shows one line of text, which the user can select and copy but not
change. `MultilineOutput` shows several lines.

@constructor Output

### ![](../source/fluid/pixmaps_svg/flTextEdit.svg) Text Edit

![Text Edit](widgets/text_edit.png)

An editor for text of any length, with scrollbars, the keyboard and
mouse editing a programmer expects, and undo. The text is in a
`TextBuffer`, which several editors and displays can share. A
`TextDisplay` (next), with these members as well.

@constructor TextEditor

@members TextEditor

The `TextBuffer` holding the text:

@members TextBuffer

### ![](../source/fluid/pixmaps_svg/flTextDisplay.svg) Text Display

![Text Display](widgets/text_display.png)

Shows text of any length from a `TextBuffer`, with scrollbars, line
wrapping, line numbers and coloured parts (a style buffer).

@constructor TextDisplay

@members TextDisplay

### ![](../source/fluid/pixmaps_svg/flFileInput.svg) File Input

![File Input](widgets/file_input.png)

An input field for a file's path, with a row of buttons above the text
for each folder in it; clicking one cuts the path back to that folder.

@constructor FileInput

@members FileInput

### ![](../source/fluid/pixmaps_svg/flSimpleTerminal.svg) Terminal

![Terminal](widgets/terminal.png)

Shows text the way a terminal does: lines added at the bottom,
scrolling up, with colours and the usual terminal escape codes. For a
program's log or the output of a command.

@constructor Terminal

@members Terminal

## 8. Menus

A menu is a list of `MenuItem`s. Each widget below that shows one is a
`Menu_`, with these members as well as those of `Widget`; `add()` adds
items, with a `/` in the label for a submenu (`"&File/&Open..."`) and a
`&` before the letter that picks it from the keyboard.

For a choice between fixed options, name them in an enum: `add!E()`
makes one item per member, and `selected!E` reads which one is picked.
In a Choice the items are its own; in a menu bar they are radio items in
a submenu. An `@ItemText("...")` on a member gives its item a text other
than the member's name. `item()` gives a member's item, to grey it out
or hide it like any other item.

```D
enum Size { small, medium, @ItemText("Extra large") extraLarge }

size.add!Size();                    // a Choice
Size s = size.selected!Size;

menubar.add!Size("View/Size");      // radio items in View > Size
menubar.select(Size.medium, "View/Size");
menubar.item(Size.extraLarge, "View/Size").deactivate();
```

@members Menu_

### ![](../source/fluid/pixmaps_svg/flInputChoice.svg) Input Choice

![Input Choice](widgets/input_choice.png)

An input field with a menu of suggestions: the user picks one or types
something else.

@constructor InputChoice

@members InputChoice

### ![](../source/fluid/pixmaps_svg/flMenuitem.svg) ![](../source/fluid/pixmaps_svg/flCheckMenuitem.svg) ![](../source/fluid/pixmaps_svg/flRadioMenuitem.svg) ![](../source/fluid/pixmaps_svg/flSubmenu.svg) Menu items

![Menu items](widgets/menu_items.png)

The entries of a Menu Bar, Menu Button or Choice: a plain item, a check
box item, a radio item (one of several), and a submenu holding more
items. In code, flags passed to `add()` make an item one or the other.

@members MenuItem

Flags:

@constants fl.menu_item

### ![](../source/fluid/pixmaps_svg/flMenubar.svg) Menu Bar

![Menu Bar](widgets/menu_bar.png)

The row of menus along the top of a window.

@constructor MenuBar

@members MenuBar

### ![](../source/fluid/pixmaps_svg/flMenuButton.svg) Menu Button

![Menu Button](widgets/menu_button.png)

A button that opens a menu.

@constructor MenuButton

@members MenuButton

### ![](../source/fluid/pixmaps_svg/flChoice.svg) Choice

![Choice](widgets/choice.png)

Shows the item that is picked, and opens the menu to pick another.

@constructor Choice

@members Choice

## 9. Browsers

### ![](../source/fluid/pixmaps_svg/flBrowser.svg) Browser

![Browser](widgets/browser.png)

A list of lines, with a scrollbar. `type()` sets whether, and how many
of, its lines can be selected: `HoldBrowser` keeps one line selected,
`MultiBrowser` several. A line's text can start with format codes for
its font and colour. A `Browser_`, with these members as well.

@constructor Browser

@members Browser

The members of `Browser_`, the base of Browser, Check Browser and File
Browser:

@members Browser_

`type()` values, sort orders and scrollbars:

@constants fl.browser_

### ![](../source/fluid/pixmaps_svg/flTree.svg) Tree

![Tree](widgets/tree.png)

Items in a hierarchy, with branches the user opens and closes. Items
are added by path (`add("Fruit/Apples")`); each is a `TreeItem`.

@constructor Tree

@members Tree

The members of a `TreeItem`:

@members TreeItem

How the tree sorts and selects:

@enum TreeSort

@enum TreeSelect

### ![](../source/fluid/pixmaps_svg/flCheckBrowser.svg) Check Browser

![Check Browser](widgets/check_browser.png)

A list of lines, each with a check box.

@constructor CheckBrowser

@members CheckBrowser

### ![](../source/fluid/pixmaps_svg/flHelp.svg) HTML View

![HTML View](widgets/html_view.png)

Shows HTML pages: headings, paragraphs, lists, tables, links, images
and fonts. `HtmlDialog` is a window with an HTML View and Back, Forward,
text size and find.

@constructor HtmlView

@members HtmlView

### ![](../source/fluid/pixmaps_svg/flMarkdownView.svg) Markdown View

![Markdown View](widgets/markdown_view.png)

Shows Markdown documents, such as a README, formatted: headings,
emphasis, lists, block quotes, code, tables, links and images. Links to
other `.md` files open them. `MarkdownDialog` is a window with a
Markdown View and Back, Forward, text size, Reload (F5) and find; Fluid's Help menu
shows fldtk's README in one.

@constructor MarkdownView

@members MarkdownView

### ![](../source/fluid/pixmaps_svg/flFileBrowser.svg) File Browser

![File Browser](widgets/file_browser.png)

A list of the files in a folder, with icons. `loadDirectory()` fills
it.

@constructor FileBrowser

@members FileBrowser

@constants fl.file_browser

### ![](../source/fluid/pixmaps_svg/flTable.svg) Table

![Table](widgets/table.png)

Rows and columns of cells, with row and column headers, which the user
can resize. A Table draws no cells itself: a program makes a subclass
and overrides `drawCell()`, which is called for each cell and header in
view. `TableRow` adds selecting rows.

@constructor Table

@members Table

What `drawCell()` is asked to draw:

@constants fl.table

## 10. Misc

### ![](../source/fluid/pixmaps_svg/flBox.svg) Box

![Box](widgets/box.png)

A box and a label, and nothing else: for text, a picture, or a frame
around other widgets.

@constructor Box

### ![](../source/fluid/pixmaps_svg/flClock.svg) Clock

![Clock](widgets/clock.png)

A clock that shows the time and keeps going. `FlClock` is a
`ClockOutput`, which shows a time it is given, with these members.

@constructor FlClock

@members ClockOutput

`type()` values:

@constants fl.clock

### ![](../source/fluid/pixmaps_svg/flProgress.svg) Progress

![Progress](widgets/progress.png)

A bar that fills as work gets done, between `minimum()` and
`maximum()`.

@constructor Progress

@members Progress

## 11. Beyond widgets

### The program: `fl.core`

The event loop, timers, threads, the clipboard, drag and drop, the
screens, the scheme, and the state of the event being handled.

@functions fl.core

### Work in the background: `fl.background`

A slow computation in a callback freezes the window until it ends.
`runInBackground()` runs it on another thread instead and hands the
result to a second function on the GUI thread, where it is safe to
change widgets. The work itself must not touch widgets. Give the
button that starts the work as the third argument, and it is greyed
out until the work is done, so it can't be started twice:

```D
button.callback((w) {
    runInBackground({ return countPrimes(10_000_000); },
                    (int n) { result.value(format("%d primes", n)); },
                    w);
});
```

To show how far the work is, let it take a `Report` and call it with
the fraction done, and set the job's `onProgress`, right after starting
it, to show that fraction:

```D
auto job = runInBackground((Report report) { return countPrimes(10_000_000, report); },
                           (int n) { result.value(format("%d primes", n)); });
job.onProgress = (fraction) { bar.value(fraction * 100); };
```

`examples/howto_run_in_background.d` shows both, with a list of progress
bars for counts started over and over, next to a callback that freezes
the window.

@functions fl.background

@members Job

### Messages and questions: `fl.ask`

Small dialogs that show a message or ask a question and wait for the
answer.

@functions fl.ask

### Choosing files

`FileChooser` is fldtk's file dialog. `NativeFileChooser` is a simpler
way to show it: set what to choose, call `show()`, read `filename()`.

@members FileChooser

@members NativeFileChooser

### Files and links: `fl.filename`

@functions fl.filename

### Drawing: `fl.draw`

For a widget that draws itself: a subclass overrides `draw()` and uses
these. Positions are in the window's coordinates.

A `draw()` that changes the clip, the colour, the font, the line style
or the transform should put it back, or whatever is drawn after it is
spoiled. The easy way is a `use...` function: it makes the change and
undoes it at the end of the block, also on an early `return` or an
exception. Keep the value it returns in a variable (`auto` will do);
the compiler refuses to let it be thrown away.

```D
override void draw()
{
    auto clip = clipTo(x, y, w, h);      // drawing stays inside the widget
    auto line = useLineStyle(lineDash, 2);
    auto font = useFont(helveticaBold, 14);
    auto col  = useColor(red);
    auto m    = saveMatrix();            // translate, scale, rotate freely
    ...
}                                        // everything is as it was before
```

@functions fl.draw

### Images

`SharedImage.get(file)` loads a picture of any kind fldtk reads (PNG,
JPEG, GIF, BMP, SVG, XPM, ICO, PNM, XBM), once per file; `image()` puts
it on a widget. Each kind of picture is a subclass of `Image`.

@members Image

@members SharedImage

### Settings: `Preferences`

Stores a program's settings between runs, for the user or for every
user of the computer.

@members Preferences

### Printing and image output

`Printer` prints; `ImageSurface` draws into an image, for saving with
`writePng()`.

@members Printer

@members ImageSurface

### OpenGL

`GlWindow` is a window that draws with OpenGL: a subclass overrides
`draw()`.

@members GlWindow
