// D transliteration of FLTK's examples/progress-simple.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh progress-simple
import fl;
import core.thread : Thread;
import core.time : dur;
import std.string : format;

// Button callback
void buttCb(Widget butt, Window win)
{
    // Deactivate the button
    butt.deactivate();                        // prevent button from being pressed again
    fl.check();                               // give fltk some cpu to gray out button
    // Make the progress bar
    win.begin();                              // add progress bar to it..
    auto progress = new Progress(10, 50, 200, 30);
    progress.minimum(0);                      // set progress range to be 0.0 ~ 1.0
    progress.maximum(1);
    progress.color(cast(Color) 0x88888800);   // background color
    progress.selectionColor(cast(Color) 0x4444ff00); // progress bar color
    progress.labelcolor(white);               // percent text color
    win.end();                                // end adding to window
    // Computation loop..
    for (int t = 1; t <= 500; t++)
    {
        progress.value(cast(float)(t / 500.0));   // update progress bar with 0.0 ~ 1.0 value
        progress.label(format("%d%%", cast(int)((t / 500.0) * 100.0))); // update progress bar's label
        fl.check();                             // give fltk some cpu to update the screen
        Thread.sleep(dur!"usecs"(1000));           // 'your stuff' that's compute intensive
    }
    // Cleanup
    win.remove(progress);                     // remove progress bar from window
    destroy(progress);                        // deallocate it
    butt.activate();                          // reactivate button
    win.redraw();                             // tell window to redraw now that progress removed
}

void main()
{
    auto win = new Window(220, 90);
    auto butt = new Button(10, 10, 100, 25, "Press");
    butt.callback((w) { buttCb(w, win); });
    win.resizable(win);
    win.show();
    fl.run();
}
