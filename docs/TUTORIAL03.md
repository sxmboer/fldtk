# Tutorial 3: buttons, shortcuts and a group, on Windows

[All tutorials](TUTORIALS.md)

> The figures in this tutorial were made just before the Run (F5)
> button was added to the properties windows, so it is missing from
> them, and the Command Prompt figure still shows the code going to
> `source\app.d`. F5 should work on Windows as described.

This tutorial makes a window with four buttons, each with a keyboard
shortcut of its own, groups them into one bar, and turns them into
radio buttons, of which only one can be down at a time. It then keeps
the choice in a variable and shows it in a dialog, and finally asks the
buttons themselves which one is down. It is done on Windows; on Linux
the steps are the same, except for the command that starts Fluid. It
assumes you have done [Tutorial 1](TUTORIAL01.md) and
[Tutorial 2](TUTORIAL02.md), so it says less about the basics of Fluid.

The commands are typed in a Command Prompt window (`cmd`). This
tutorial assumes the fldtk folder is `fldtk` in your user folder
(`%USERPROFILE%\fldtk`, for instance `C:\Users\you\fldtk`), and keeps
the project in `%USERPROFILE%\fluidtutorials\tutorial03`.

## 1. Preparing fldtk

    cd %USERPROFILE%\fldtk
    rdmd buildfluid.d

This builds the fldtk library and Fluid, `fluid.exe`.

## 2. Starting Fluid

    %USERPROFILE%\fldtk\fluid.exe

Double-clicking `fluid.exe` in File Explorer starts it too. To keep it
at hand, right-click `fluid.exe` and choose Pin to Start; from then on
it is in the Start menu.

Fluid opens with an empty design. The project folder doesn't exist
yet: Fluid asks for it the first time you press F5, in step 6.

## 3. Creating the window and the first button

1. **The function.** Choose New > Code > Function, or click
   ![Function](../source/fluid/pixmaps_svg/flFunction.svg) in the Widget
   Bin. Its "Function Name and Args:" is blank, so it is `main()`;
   click Close.
2. **The window.** With `main()` selected, choose New > Group > Window,
   or click ![Window](../source/fluid/pixmaps_svg/flWindow.svg). In its
   properties, on the GUI tab, set the Label to `Four Buttons`, and
   click Close. The window's size does not matter; drag its edge or
   corner to make it larger or smaller whenever you like.
3. **The first button.** With the window selected, choose New > Buttons
   > Button, or click ![Button](../source/fluid/pixmaps_svg/flButton.svg).
   In its properties, on the GUI tab:
   - set the Label to `Button &1`. An `&` in a label underlines the
     character after it: the button shows "Button 1" with the 1
     underlined, a hint at its shortcut;
   - click the Shortcut field, then press the 1 key. The field shows
     `1`: pressing 1 while the program runs is the same as clicking the
     button.

   ![The first button's properties: label and shortcut](tutorial03/fig01.png)

   Click Close. Where the button sits does not matter: drag it to place
   it as you like.

## 4. Making four buttons

1. **A copy.** With the first button selected, press Ctrl first and
   keep it held, then press the mouse button on the button and drag it
   down. The order matters: pressing Ctrl only after the mouse button
   moves the original instead of copying it. Done in this order, the
   original stays where it is and a copy follows the mouse; the tree now
   shows two buttons. Drag until the copy
   snaps into place just below the original, with its top edge touching
   the original's bottom edge: no gap between them and no overlap. While
   you drag, guide lines show where it will snap. Keep the copy straight
   below the original, at the same left edge. The buttons have to touch
   like this for step 7, where they are joined into one bar.

   The copy has the same label and shortcut as the original, so change
   them in its properties: Label `Button &2`, Shortcut 2. (Double-click
   a button, in the window or in the tree, to open its properties.)
2. **Two more.** Do the same twice more, each time Ctrl-dragging the
   newest button until its copy snaps against the bottom of that one:
   the third gets `Button &3` and 3, the fourth `Button &4` and 4. If
   the window is too small for the fourth button, make it taller first.

   ![The four buttons stacked](tutorial03/fig04.png)

The usual ways of copying work too: Edit > Copy (Ctrl+C) and Edit >
Paste (Ctrl+V), or Edit > Duplicate (Ctrl+U), which copies the selection
in one step. Both place the copy exactly on top of the original, so the
window seems unchanged until you drag the copy away. Until then the tree
shows two buttons, and in the window the button is hatched:

![The copy lying on top of the first button](tutorial03/fig02.png)

Fluid hatches every part of a widget that overlaps another widget, since
widgets on top of each other are almost always a mistake: the one on top
hides the other, and takes its clicks. Here is what that looks like for
widgets that partly overlap:

![Hatched overlaps](tutorial03/fig03.png)

There is also a quicker way to make the stack, with a feature added
after this tutorial was first written. Turn on New > Place New Widgets
Below:

![New > Place New Widgets Below](tutorial03/fig23.png)

With this on, a widget made while another one is selected goes right
below it, instead of to its right. Place the first button anywhere,
keep it selected, and click
![Button](../source/fluid/pixmaps_svg/flButton.svg) (Button) in the
Widget Bin three times: each new button lands just below the one made
before it, touching it, the same as the four stacked above. (If the
window is too small for four, the next one starts a new column beside
them instead; make the window taller first.) New buttons get the label
`Button` and no shortcut, so give each its label and shortcut as in
step 3. Fluid remembers the setting, so turn it off again for designs
in which new widgets should go to the right.

## 5. Adding callbacks

A button does nothing when clicked until it has a callback: D code that
runs on each click. Open the first button's properties, and on the D
tab click "callback" and type:

    writeln("Button 1 pushed");

![The first button's callback](tutorial03/fig05.png)

Give the other three their own: `writeln("Button 2 pushed");`,
`writeln("Button 3 pushed");` and `writeln("Button 4 pushed");`.

To try the design without building anything, click Live Resize at the
bottom of a properties window. Fluid opens a copy of the window, "Fluid
Live Resize", in which the buttons can be clicked and the window can be
resized. Callbacks do not run there: it shows how the window looks and
behaves, not what the program does. Click Exit Live Resize to close it.

![Live Resize](tutorial03/fig06.png)

## 6. Saving and running

To quickly run the actual compiled program, press F5 in any of the
Fluid windows. Building on Windows works the same as on Linux, as
shown in Tutorials 1 and 2.
For this tutorial, a single file project is sufficient, but either
option will work.

The design has no file name yet, so Fluid first asks where to save
it. Go to the folder where you keep your tutorials, here `%USERPROFILE%\fluidtutorials`, make a new folder
`tutorial03` with the folder button at the top right, and save the
design in it as `fourbuttons`. Typing `fourbuttons` is enough: Fluid
adds `.fl` itself.

Then Fluid asks how to build the program. Click Single File, as in
Tutorial 1, and Fluid writes the design's code to `fourbuttons.d`,
next to `fourbuttons.fl`. Or click Set Up Project, as in Tutorial 2,
and Fluid makes the folder `tutorial03` a dub project, with the
design's code in `source\fourbuttons.d`; click Close when it has said
what it did. Either way, Fluid builds the program, with dub's output
in the Run window, and starts it. The window appears:

![The program's window](tutorial03/fig09.png)

Click the buttons, and press 1 to 4: each prints a line in the Run
window.

If the Run window shows error messages from the compiler instead,
check the callbacks: Fluid copies each one into the D code exactly as
typed, so each has to be correct D, exactly as above. Correct them in
Fluid and press F5 again.

From now on, F5 saves the design, builds the program and starts it
without asking. To build in the Command Prompt instead, see
[Building in the Command Prompt](#building-in-the-command-prompt) at
the end of this tutorial.

The finished design is the same as `fourbuttons_1.fl` in fldtk's
`docs/tutorial03` folder (apart from the Code File, if you chose
Single File).

## 7. Grouping the buttons

The four buttons are separate widgets, each with its own border. Put
into a group and made compact, they become one bar.

1. **Select the four buttons.** Click the first one in the tree, then
   Shift-click the fourth.
2. **Group them.** Choose Edit > Group (F7). Fluid puts the four buttons
   in a new group, sized to fit around them, inside the window. The tree
   shows it as a Group holding the four buttons.
3. **Make them compact.** Select the four buttons again, open their
   properties (Edit > Properties..., F1), and on the Style tab turn on
   Compact. The change applies to all four at once. A compact button
   draws the border of the whole group it is in, but shows only its own
   part of it, with a short line where it meets the next button, so the
   four together look like one bar with a single border around it.

   This only works when the buttons are inside a group that fits
   tightly around them, as the group from Edit > Group does. Compact
   buttons placed directly in the window draw the border of the whole
   window instead: its edges are far away from the buttons, so the
   buttons lose their outer border altogether, and only the short lines
   between them remain.

   ![The group, and the Style tab with Compact on](tutorial03/fig11.png)

   Live Resize shows the bar:

   ![The bar of buttons in Live Resize](tutorial03/fig12.png)

The buttons work as before; only their look changed.

## 8. Making radio buttons

A plain button springs back up when you let go of it. A radio button
stays down, and only one radio button in a group can be down at a
time: pressing one releases the one that was down before, like the
station buttons of an old car radio.

Which buttons belong together is decided by the group they are in:
pressing a radio button releases only the radio buttons in the same
group, its siblings in the tree. So all the buttons of one set of
choices have to be inside the same group. Here the group from step 7
already holds the four buttons. A radio button outside it, for
instance directly in the window, would not release them, nor be
released by them. The same rule lets a window have several independent
sets of choices: give each set a group of its own.

1. **Select the four buttons** in the tree, as in step 7.
2. **Make them radio buttons.** Open their properties (F1), and on the
   D tab, in the Class row, set the choice next to the class name to
   `Radio`. As with Compact, the change applies to all four at once.

   ![The D tab with the subtype set to Radio](tutorial03/fig13.png)

   In Live Resize, the button you click stays down, and the one that
   was down comes back up:

   ![Button 3 down in Live Resize](tutorial03/fig14.png)

3. **One button down at the start.** When the program starts, no button
   is down yet. To start with the first one down, select it alone, and
   on the GUI tab set Value to `1`. A button's value is 1 when it is
   down and 0 when it is up.

   ![Value 1 for the first button](tutorial03/fig15.png)

4. Press F5 again. Click the buttons, or press 1 to 4:
   the button you choose stays down and the one that was down comes
   back up. Each still prints a line, as before.

## 9. Remembering the choice

A program usually needs to know which option is chosen, not just print
it at the moment of the click. This step keeps the chosen option in a
variable, and adds a button that shows it in a dialog.

1. **A variable for the choice.** Select the window, open its
   properties, and on the D tab click "setup". Type:

       // the scope has to be higher than the buttons
       int selected;

   ![The window's setup code](tutorial03/fig16.png)

   A window's setup code runs right after the window is made, before
   the widgets inside it. A variable declared there can be used in the
   callbacks of every widget inside the window, because Fluid writes
   their code after it, in the same block. In a button's own setup, it
   would be visible only to that button.
2. **Store the choice.** Add a line to each button's callback that
   stores its number: `selected = 1;` for the first button,
   `selected = 2;` for the second, and so on. The first button's
   callback becomes:

       selected = 1;
       writeln("Button 1 pushed");

3. **A button that shows the choice.** Select the window and add a
   Return Button (New > Buttons > Return Button) outside the group, to
   the right of it, with Label `Check`. With the window selected, the
   new button lands near the window's top-left corner, on top of the
   group, so drag it to the right of the group. A return button is pressed by
   the Enter key as well as by a click. Its callback:

       message(format("Button %s is selected", selected));

   `message()` shows a small dialog with a text and a Close button. It
   takes one piece of text, so `format()` puts the number into it: each
   `%s` in the first argument is replaced by the next argument. Without
   a `%s` for `selected`, the program stops with a `FormatException`
   ("Orphan format arguments") when the button is pressed.

   ![The window with the Check button](tutorial03/fig17.png)

   Edit > Show Code View (Alt+C) shows where `selected` ends up in the
   generated code: right after the window is made, before the group and
   the buttons whose callbacks use it.

   ![The Code View with the variable selected](tutorial03/fig18.png)

4. Press F5 again.

Choose a button, then press Enter or click Check:

![The dialog showing the selected button](tutorial03/fig19.png)

The finished design is the same as `fourbuttons_2.fl` in fldtk's
`docs/tutorial03` folder (apart from the Code File, if you chose
Single File).

## 10. Asking the buttons themselves

Run the program and press Check right away, before clicking any
button. Button 1 is down, as set in step 8, yet the dialog says
"Button 0 is selected".
`selected` only knows what the buttons' callbacks told it, and Button 1
was put down by its Value setting, not by a click, so no callback ran.
A D `int` starts at 0. The buttons always know their own state, so this
step asks them instead, and the variable is no longer needed.

1. **Name the buttons.** So far, each button has had the automatic
   variable name `o` by default: as
   [Tutorial 2](TUTORIAL02.md) showed, Fluid makes each button in a
   block of its own, in a variable called `o`, which only that button's
   own code can use. But in this tutorial, the Check button's callback
   has to reach the four buttons, so each needs a name of its own.
   Select each button in turn, and on the D tab, in the Name row, type
   `b1`, `b2`, `b3` and `b4`. A named widget becomes a variable in the
   generated code, which any callback can use.

   ![The D tab with the name b1](tutorial03/fig20.png)

2. **Remove what is no longer needed.** Clear the window's setup code,
   and the four buttons' callbacks.
3. **Ask them.** Change the Check button's callback to:

       long selected;
       foreach (i, b; [b1, b2, b3, b4])
         if (b.value())
           selected = i + 1;

       message(format("Button %s is selected", selected));

   ![The Check button's new callback](tutorial03/fig21.png)

   `[b1, b2, b3, b4]` is a list of the four buttons. `foreach` takes
   them one at a time: `b` is the button, and `i` its place in the list,
   counting from 0. `b.value()` is true when the button is down, and
   `i + 1` turns places 0 to 3 into buttons 1 to 4. `i` is a large
   number type, which fits in a `long` but not in an `int`; that is why
   `selected` is a `long` here. The same, without the list, would be:

       long selected;
       if (b1.value()) selected = 1;
       if (b2.value()) selected = 2;
       if (b3.value()) selected = 3;
       if (b4.value()) selected = 4;

   The Code View shows the four named buttons as variables at the top
   of the generated code, outside `main()`:

   ![The Code View with the variables b1 to b4](tutorial03/fig22.png)

   Declared there, at the level of the module, the names can be used by
   every callback in the file, whichever block it is in. The buttons
   themselves are still made inside `main()`, each in its own block,
   with `b1 = new Button(...)` where an unnamed one has
   `auto o = new Button(...)`. The choice next to the Name sets whether
   other modules can use them too: with global, the default, any module
   that imports this one can use `b1`. A function in such a module, like
   the ones in Tutorial 2's `actions.d`, then doesn't need the button
   passed to it as `o`: it can read the button's state directly with
   `b1.value()`. With local, Fluid writes
   `private Button b1;`, so other modules cannot see it. That keeps the
   window's widgets shielded from the rest of the program.

4. Press F5 again.

Press Check right away: the dialog now says Button 1, the one that is
down. Choose another button and press Check again: it names that one.

The finished design is the same as `fourbuttons_3.fl` in fldtk's
`docs/tutorial03` folder (apart from the Code File, if you chose
Single File).

## Summary

You have made a window with four buttons and given each a label with
an underlined letter and a keyboard shortcut of its own. You have
copied buttons by Ctrl-dragging them, and made the same stack with
Place New Widgets Below. You have given the buttons callbacks, tried
the design with Live Resize, and built and run the program with F5.
You have grouped the buttons and made them compact, so they look like
one bar, and made them radio buttons, of which only one can be down at
a time. Finally, you have kept the chosen option in a variable declared
in the window's setup code, and then asked the buttons themselves by
giving them names, which makes them variables that every callback in
the file, and, with global, other modules too, can use.

This concludes Tutorial 3. Additional information is provided below.

## Building in the Command Prompt

The program builds without Fluid too. In the Command Prompt, go to the
project folder:

    cd %USERPROFILE%\fluidtutorials\tutorial03

For a single file, write the code from the design, then build and run
it, as in Tutorial 1's [Rebuilding and launching a project
manually](TUTORIAL01.md#rebuilding-and-launching-a-project-manually):

    %USERPROFILE%\fldtk\fluid.exe -c fourbuttons.fl
    dub run --single fourbuttons.d

For a dub project, one command does it all:

    dub run

dub then runs Fluid first, to write `source\fourbuttons.d` from the
design (Tutorial 2's [What dub.sdl
says](TUTORIAL02.md#what-dubsdl-says) explains how), so saving the
design in Fluid is enough before building this way.

Either way, the program's window appears, and the buttons print their
lines in the Command Prompt:

![The Command Prompt after a few clicks and shortcuts](tutorial03/fig10.png)
