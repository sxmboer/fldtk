// D transliteration of FLTK's test/help_dialog.cxx.
// Build: rdmd buildsamples.d test help_dialog
//
// Notes on this transliteration:
//  - Fl_Help_Dialog (fl.help_dialog.HelpDialog) is real, ported fldtk
//    API, used directly below.
//  - Fl_GIF_Image (fl.gif_image.GifImage) decodes a static single frame;
//    `GifImage.animate` below is a flag with no playback effect on its
//    own. Real animated-GIF playback exists too now
//    (fl.anim_gif_image.AnimGifImage), but this sample still drives its
//    own animation manually via a timer (see `cbRefresh()` below)
//    instead of using it.
//  - FLTK's cb_refresh() timeout callback takes a void* d (the help
//    dialog pointer) purely so the C function pointer has something to
//    close over; per CONVENTIONS.md's callback convention this becomes a D
//    closure that captures `help` directly, dropping the void* entirely.
import fl;

void main(string[] args)
{
    GifImage.animate = true; // create animated shared .GIF images

    auto help = new HelpDialog();

    void cbRefresh()
    {
        // trigger a redraw of the window to see animated GIF's
        if (fl.firstWindow() !is null)
            fl.firstWindow().redraw();
        fl.repeatTimeout(1.0 / 10, &cbRefresh);
    }

    int i;
    fl.argsToUtf8(args); // for MSYS2/MinGW
    if (!fl.args(args, i)) fl.fatal(fl.argsHelp);
    string fname = (i < args.length) ? args[i] : "help_dialog.html";

    help.load(fname); // TODO: add error check (when load() returns int instead of void)

    help.show(); // HelpDialog.show() takes no args -- see fl.help_dialog's
    // own doc comment on why show(argc, argv) wasn't ported

    fl.addTimeout(1.0 / 10, &cbRefresh); // to animate GIF's
    fl.run();

    destroy(help);
}
