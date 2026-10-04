// D transliteration of FLTK's examples/animgifimage-simple.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh animgifimage-simple
import fl;
import std.stdio : writefln;

void main(string[] args)
{
    auto win = new DoubleWindow(400, 300, "AnimGifImage demo");

    // prepare a canvas (widget) for the animation
    auto canvas = new Box(20, 40, win.w() - 40, win.h() - 80, "Hello from FLTK GIF-animation!");
    canvas.alignment(alignTop | alignImageBackdrop);
    canvas.labelsize(20);

    win.resizable(win);
    win.end();
    win.show();

    // Create and load the animated gif as image
    // of the `canvas` widget and start it immediately.
    // We use the `DONT_RESIZE_CANVAS` flag here to tell the
    // animation *not* to change the canvas size (which is the default).
    string defaultImage = "../test/images/fltk_animated.gif";
    auto animgif = new AnimGifImage(args.length > 1 ? args[1] : defaultImage,
            canvas, AnimGifImage.dontResizeCanvas);
    // resize animation to canvas size
    animgif.scale(canvas.w(), canvas.h(), /*canExpand*/ true, /*proportional*/ true);

    // check if loading succeeded
    writefln("%s: ld=%d, valid=%d, frames=%d, size=%dx%d",
            animgif.name(), animgif.ld(), animgif.valid(),
            animgif.frames(), animgif.canvasW(), animgif.canvasH());
    if (animgif.valid())
        fl.run();
}
