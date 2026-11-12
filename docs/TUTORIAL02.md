# Tutorial 2: a Fluid program as a dub project

[All tutorials](TUTORIALS.md)

[Tutorial 1](TUTORIAL01.md)'s program is one file. A real program
grows: it gets modules of its own for the work it does, next to the
code Fluid writes for the window, and perhaps other packages it uses.
dub, D's build tool, handles all of that as a project. In this
tutorial Fluid makes a dub project for a small program, and the
program's buttons call functions in a module of your own. It assumes
you have done Tutorial 1, so Fluid is built and you know your way
around it; no earlier experience with dub is needed.

In this tutorial the fldtk folder is `~/fldtk`; use your own path
everywhere it appears.

## What dub is

dub is D's build tool and package manager, installed with the dmd D compiler.
A dub project is a folder that holds:

- `dub.sdl` (or `dub.json`, the same thing in another notation): the
  project's name, the packages it depends on, and any extra build
  steps;
- `source/`: the program's `.d` files.

`dub build` compiles every `.d` file in `source/`, together with every
package the project depends on, into one program. `dub run` builds it
and starts it. dub only rebuilds what has changed. You don't have to list your
source files anywhere: a new `.d` file placed in the `source/` directory
automatically becomes part of the program.

This project depends on one package, fldtk. dub uses the fldtk library
in your fldtk folder, and passes your program everything it needs to
use it: import paths, version flags and the libraries to link. Fluid
writes the `dub.sdl` for you.

## 1. Starting a dub project

Start Fluid:

    ~/fldtk/fluid

The Widget Bin opens with it:

![The Widget Bin](tutorial02/fig01.png)

Click ![Window](../source/fluid/pixmaps_svg/flWindow.svg) (Window) and
click Create a Function, as in Tutorial 1. With the window selected,
click ![Button](../source/fluid/pixmaps_svg/flButton.svg) (Button)
twice. Give the first button the Label `Say Hello` and the second the
Label `Counter` (GUI tab). The tree shows `main()` with the window and
the two buttons:

![The window with the two buttons](tutorial02/fig02.png)

There is a quicker way to add a widget exactly where you want it: a
right-click in the window. See [Working with the right-click
menu](#working-with-the-right-click-menu) at the end of this tutorial.

The buttons don't do anything yet; their callbacks come in step 3.

Press F5. The design has no file name yet, so Fluid first asks where
to save it. Go to the folder where you keep your tutorials, here
`~/fluidtutorials`, make a new folder `tutorial02` with the folder
button at the top right, and save the design in it as `hello`:

![Saving hello.fl in the new folder tutorial02](tutorial02/fig03.png)

The project folder is the folder the design is in, so give every dub
project a folder of its own. The design's name, `hello`, becomes the
name of the project and of the program.

Then Fluid asks how to build the program:

![Set Up Project or Single File](tutorial02/fig04.png)

This time, click Set Up Project. Fluid makes the folder `tutorial02` a
dub project for this design, and says what it did:

![What Set Up Project did](tutorial02/fig05.png)

- it wrote `dub.sdl`, the project's description for dub, and a
  `.gitignore` (the two files `dub init`, dub's own command for a new
  project, writes);
- it set the design's Code File to `source/hello.d`, in the folder
  where dub looks for the program's code (Edit > Settings..., Project
  tab), and saved the design.

Click Close. Fluid writes `source/hello.d`, builds the project with
dub, with dub's output in the Run window, and starts the program: the
window titled `hello`, with its two buttons. Close it.

From now on, F5 builds and runs this project without asking.

F5 took you through every step, one question at a time. The File menu
can do the same steps one by one; see [Setting up from the File
menu](#setting-up-from-the-file-menu) at the end of this tutorial.

## 2. What is in the project

The folder `tutorial02` now holds:

    tutorial02/
      dub.sdl            the project's description for dub
      .gitignore         the files git should leave out
      hello.fl           the design, made with Fluid
      source/
        hello.d          the D code for the design, written on every build
      hello              the program (hello.exe on Windows)

The design and the program's own code are kept apart:

- `hello.fl` is the window and what is in it. You change it in Fluid.
- `source/hello.d` is written from `hello.fl` on every build. Don't
  change it by hand: the next build overwrites it.
- Everything else your program does, its business logic, goes in `.d`
  files of your own in `source/`, next to `hello.d`. dub picks up every
  `.d` file placed there; there is nothing to register.

`dub.sdl` tells dub how to build the program. You don't need to change
it to follow this tutorial; [What dub.sdl says](#what-dubsdl-says), at
the end, goes through it line by line.

## 3. Setting the callbacks

In Tutorial 1 the callbacks held the code itself. For larger projects, it
becomes impractical to put large functions in the `.fl` file. In this tutorial,
they only call a function, which you write in a module of your own in the next
step. Double-click the Say Hello button, and on the D tab set its callback to:

    sayHello();

![The callback of Say Hello](tutorial02/fig07.png)

Click the Counter button and set its callback to:

    countClick(o);

![The callback of Counter](tutorial02/fig08.png)

In a callback, `o` is the widget the callback belongs to, here the Counter
button. Passing it to `countClick()` hands that function the button itself, so
it can read from it or change it. The callback calls your code, and your code
changes the button. Step 5 shows where `o` comes from.

Press F5. The build fails:

![The build fails: undefined identifier sayHello](tutorial02/fig09.png)

The compiler doesn't know `sayHello` and `countClick`: they don't exist
yet. (The errors under each one, that none of the overloads of
`callback` are callable, follow from the same mistake.)

## 4. Writing a module of your own

The functions go in a new file, `source/actions.d`, with this code:

    import fl;
    import std.format : format;

    void sayHello()
    {
        message("Hello from actions.d!");
    }

    int clicks;

    void countClick(Button button)
    {
        clicks++;
        button.label(format("Clicks: %d", clicks));
    }

- The module is called `actions`, after its file name. Other modules
  use that name to import it.
- `import fl;` makes fldtk available in this module: `message()`, and
  `Button` for `countClick()`'s parameter. Every module that uses fldtk
  imports it.
- The `o` in the Counter button's callback corresponds to `button` in
  the `countClick` function.
- `int clicks;` is an integer variable of the module. It keeps its value between
  clicks, for as long as the program runs. Its value is incremented upon each
  call of `countClick` and the label of the button is changed using the
  `button.label` method to a formatted string with that number in it.

Make actions.d in one of two ways:

- copy the code above, paste it into a new file in a text editor, and
  save that as `actions.d` in the project's `source` folder; or
- copy the finished file from the fldtk folder, on Linux:

      cp ~/fldtk/docs/tutorial02/actions.d ~/fluidtutorials/tutorial02/source/

  or, on Windows, in the Command Prompt:

      copy %USERPROFILE%\fldtk\docs\tutorial02\actions.d %USERPROFILE%\fluidtutorials\tutorial02\source\

  or use File Explorer to copy the file.

Either way, it has to be in `source/`, next to `hello.d`, not in the
project folder itself. The project now holds:

    tutorial02/
      dub.sdl            the project's description for dub
      .gitignore         the files git should leave out
      hello.fl           the design, made with Fluid
      source/
        actions.d        NEW: your code
        hello.d          the D code for the design, written on every build
      hello              the program (hello.exe on Windows)

Press F5 again. **It still fails!** And the errors are the same:

![Still undefined identifier sayHello](tutorial02/fig10.png)

Why is this? Even though `sayHello` is defined in `actions.d` now,
the callbacks in `hello.d` don't know where to find it.
Neither D nor dub searches through all the modules to find the needed
functions, so you have to tell them where to look.
A module only sees the functions that it imports: `hello.d` has to import
`actions`. To do this in Fluid, choose New > Code > Declaration, or click
![Declaration](../source/fluid/pixmaps_svg/flDeclaration.svg)
(Declaration) in the Widget Bin. The Declaration is added below
`main()`, and its properties open. Replace the automatically generated example `int x;` in the
Declaration field with:

    import actions;

![The Declaration import actions;](tutorial02/fig11.png)

The compiler should now be able to find the functions we need.

## 5. Running it

Press F5. This time dub should compile `hello.d` and `actions.d` together and
the program should launch. If it fails, see [Compilation
errors](#compilation-errors) at the end of this tutorial.

Click Say Hello, and the message should appear:

![The message from actions.d](tutorial02/fig12.png)

Click Counter a few times; it counts the number of times it has been clicked:

![The button after three clicks](tutorial02/fig13.png)

To look under the hood and see how Fluid builds the interface, choose
Edit > Show Code View (or press Alt+C). It shows the code Fluid writes
to `hello.d`:

![The Code View](tutorial02/fig14.png)

Notice how the nested layout of the code tree (main, Window, Button, Button) corresponds to
the indentation levels in the generated source code.

Two things in the code are worth a closer look:

**The Declaration.** In the tree, `import actions;` sits below
`main()`, but in the code it is at the top, with `import fl;` and
`import std;`. Fluid writes a Declaration at the top level of the file,
outside every function, whatever its place in the tree, so you don't
have to worry about where it ends up there. A Declaration is for any
code that belongs at the top of the file: an import, as here, or a
variable or a constant that the whole file uses.

**Where `o` comes from.** Each button is made in a block of its own,
in a variable called `o`:

    {
        auto o = new Button(89, 25, 64, 22, "Counter");
        o.callback((raw_) {
            countClick(o);
        });
    }

The block between the curly braces defines a **scope**. Note that within the
scope of the button, the variable `o` refers to the new Button. That
variable is only defined within this block of code. Every button
gets its own `o`. D does not allow the same variable to be defined twice within
the same scope. Therefore, Fluid separates them by defining a separate scope for each.

So `o` is the Counter button, and `o.callback(...)` gives it its callback: the
code between the inner braces is technically called a delegate and that portion of
code is executed on every click. All it does in this case is forward the
execution to `countClick`. Your callback code is copied into it as typed, so `o`
in a callback is always the widget it belongs to. `countClick(o)` passes that
button on to `countClick()`, which gets it as its parameter `button`.

Here `countClick()` changes the button's own label. More often, a
callback passes on the widget's value instead: what was typed in an
input field, or where a slider stands. For a Slider, for instance, the
callback could be `setVolume(o.value());`, with `setVolume()` a
function of yours that takes a `double`. Your function then only needs
the value, not the widget, and stays independent of the window.

As the program grows, it gets more modules in `source/`, each one a
`.d` file imported by the modules that use it. `actions.d` knows
nothing about the window: it could be a module you already had. That is
also how you give an existing program a GUI: design the window in Fluid
and have its callbacks call the functions the program already has.

## Summary

You have had Fluid set up a dub project. You have learned what each file in it
is for, and split the program into the design's code, which Fluid writes, and a
module of your own, which the callbacks call. You have also learned how the GUI
can communicate parameters back and forth with other modules through the
callback functions. This split gives a brief view of how larger projects are
built. Finally, you have seen how to inspect the code Fluid generates.

This concludes Tutorial 2. Additional information is provided below.

## Building in a terminal

A dub project builds without Fluid too. Once Fluid has set it up, all
it takes is `dub run` in the project folder, which builds the program
and starts it:

    $ cd ~/fluidtutorials/tutorial02
    $ dub run
         Pre-gen Running commands for hello
    fluid: /home/you/fluidtutorials/tutorial02/hello.fl -> /home/you/fluidtutorials/tutorial02/source/hello.d
        Starting Performing "debug" build using /usr/bin/dmd for x86_64.
        Building hello ~master: building configuration [application]
         Linking hello
         Running hello

The program's window opens, the same as with F5. `dub build` only
builds it; `./hello` (`hello.exe` on Windows) then starts it.

dub runs Fluid itself first (the `preGenerateCommands` line, see
[What dub.sdl says](#what-dubsdl-says)), so saving
the design in Fluid is enough before building this way.

When changing .d files in your business logic using your own text editor,
`dub run` guarantees the newly edited code is used to recompile the program binary.

## What dub.sdl says

The `dub.sdl` that Fluid wrote in step 1 reads:

    name "hello"
    description "A program made with Fluid and fldtk."
    authors "you"
    license "proprietary"
    targetType "executable"
    dependency "fldtk" path="/home/you/fldtk"
    subConfiguration "fldtk" "program"
    preGenerateCommands "\"$FLDTK_PACKAGE_DIR/fluid\" -c \"$PACKAGE_DIR/hello.fl\"" platform="linux"
    preGenerateCommands "\"$FLDTK_PACKAGE_DIR\\fluid.exe\" -c \"$PACKAGE_DIR\\hello.fl\"" platform="windows"

The first four lines name the project and describe it; change them as
you like (`authors` is your user name). The others, one by one:

- `targetType "executable"`: the project is a program.
- `dependency "fldtk" path="/home/you/fldtk"`: where your fldtk folder
  is. Fluid writes the folder Fluid itself is in (or the one in Edit >
  Settings..., General, fldtk Folder) as a full path (on Windows, for
  instance, `C:/Users/you/fldtk`), so the project folder can be moved
  anywhere. (dub doesn't understand `~` in this path.)
- `subConfiguration "fldtk" "program"`: how the program uses fldtk. A
  dub package can be built in several ways, called configurations;
  `program` is the one fldtk has for programs that use it. It links
  your program to the library in the fldtk folder, without building it
  again. On Linux, the library is a shared library,
  `~/fldtk/libfldtk.so`: every program built this way uses that one
  file, so rebuilding fldtk updates all of them, and the program finds
  it there when it runs. On Windows, the library, `fldtk.lib`, is
  linked into the program itself.
- `preGenerateCommands`: a command dub runs before every build. Here it
  is `fluid -c hello.fl`, which writes `source/hello.d` from the
  design, so a build started in a terminal also uses the latest design.
  `$FLDTK_PACKAGE_DIR` is dub's name for the fldtk folder and
  `$PACKAGE_DIR` for your project folder. The `\"` are quotes inside
  the quoted command, so folder names with spaces work. `platform=`
  picks the line for the system you build on.

## Setting up from the File menu

In step 1, F5 asked every question in turn. The File menu does the
same steps one by one: File > Save (Ctrl+S) saves the design in its new
folder, then File > Set Up dub Project... makes that folder a dub
project, without building or running anything:

![File > Set Up dub Project...](tutorial02/fig06.png)

## Working with the right-click menu

Fluid has a right-click menu in two places: in the design window and
in the tree. One of its entries, Change To, is also in the properties
window.

**In the design window.** Right-click on an empty spot in the window
and choose New > Buttons > Button.... The new button lands where you
clicked, instead of at the spot the Widget Bin picks. Every kind of
widget in the New menu can be added this way.

![The right-click menu in the window: New > Buttons > Button...](tutorial02/fig15.png)

Right-clicking on a widget that is already selected gives a menu with
two entries. Change To turns the widget into another kind of widget,
here a Button into a Return Button, keeping its label, name, callback
and other settings; Tutorial 4 uses it. New is the same menu as
before.

![Right-clicking a selected button: Change To and New](tutorial02/fig16.png)

**In the tree.** Right-click on an item in the tree. For a widget, the
menu starts with the same Change To, followed by Cut, Copy, Paste,
Duplicate and Delete, and Earlier and Later, which move the item up or
down among its neighbors; they are the same commands as in the Edit
menu, with the same shortcuts. A right-click selects the item first,
unless it is already part of the selection, in which case the command
applies to the whole selection.

![The tree's right-click menu on a button](tutorial02/fig17.png)

**In the properties.** Change To is also in the widget's properties
window, as Change to: at the bottom of the Style tab. It shows the
widget's current kind; pick another one to change it. Widgets that
can't change kind don't have it.

![Change to: on the Style tab](tutorial02/fig18.png)

Ctrl+Z undoes each of these steps.

## Variations

- **A dub project you already have.** Save the design in the project's
  folder, next to its `dub.sdl`, and press F5 (or choose File > Set Up
  dub Project...). Fluid completes the project's `dub.sdl`: it adds the
  lines it lacks, at its end, and changes nothing else. It sets the Code
  File to `source/<design name>.d`, asking first when that file exists,
  and removes the placeholder `source/app.d` that `dub init` writes,
  whose `main()` would clash with the design's. An `app.d` you changed
  stays.

  An existing program usually has a `main()` of its own, with
  everything that comes with it: reading the command line, setting
  things up, perhaps a way of working in which the window is only one
  option, such as a form to type the program's parameters in instead of
  reading them from an input file. Keep that `main()`, and give the
  design's Function a name of its own instead, for instance
  `makeWindow()`.
  Fluid then writes a function that builds the window and returns it.
  Your `app.d` imports the design's module, named after its file, and
  its `main()` shows the window and runs the program:

      import fl;
      import hello;   // source/hello.d, the design's code
      ...
      auto window = makeWindow();
      window.show(args);
      fl.run();

  (`args` is `main(string[] args)`'s parameter; with a `main()`
  without parameters, use `window.show();`.) Tutorial 7 ([coming
  soon](TUTORIALS.md)) makes this a program of its own: the window as
  a class, started by a `launchGUI` function the program calls.

  A project described by `dub.json` is not changed; Fluid shows the
  entries to add to it.
- **Other builds of the library.** `program` uses the default fldtk
  library: with Cairo and Pango on Linux, without them on Windows. For
  another one, name its configuration instead of `program`:
  `linux-no-cairo` (Linux without Cairo and Pango) or `windows-cairo`
  (Windows with them; the Cairo and Pango libraries must be built
  first). See `BUILDING.md` for details. dub then builds the library for
  the project and, on Linux, puts a copy of `libfldtk.so` in the project
  folder; add this line so the program finds it there:

      lflags "-rpath=$$ORIGIN" platform="linux"

  (`$$` is how you write a plain `$` in `dub.sdl`.)

## Compilation errors

Mistakes happen all the time when programming: a forgotten `;`, a
forgotten parenthesis or a mistyped function name. All will cause the compiler
to produce an error and quit. The output of the compiler will be shown in the
Run window. If the Run window shows errors, look for:

- `undefined identifier sayHello` (or `countClick`): `hello.d` doesn't
  import `actions` (check the Declaration), or the function isn't in
  `actions.d` (check its name).
- `undefined reference to actions.sayHello()` (or `ModuleInfo for
  actions`), from the linker at the end of the build: `actions.d` is in the
  project folder instead of in `source/`. The compiler still finds it there for
  the import, but dub only builds the files in `source/`, so the functions are
  missing from the program. Move `actions.d` into `source/`.
- `message matches conflicting symbols` (or another name of yours): the
  code Fluid writes imports all of fldtk and of D's standard library (`import
  fl;` and `import std;`), so a function of yours called, say, `message` or
  `write` clashes with theirs. Give your functions names of their own, like
  `sayHello` and `countClick`. Or, where you call such a function, say which
  one you mean by putting its module's name in front of it, a fully qualified
  name: `fl.message("...")` for fldtk's, `actions.message("...")` for yours.

The first compiler error is usually where you want to look first.
To find what causes the issue, pull up the code view and search for a keyword
listed in the error report. Or, if you recognize the name of a widget, you can
click on that widget and the code view should scroll immediately to the
corresponding block of code that creates that widget.

