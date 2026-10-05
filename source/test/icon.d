// D transliteration of FLTK's test/icon.cxx.
// Build: rdmd buildsamples.d test icon
//
// Notes on this transliteration:
//  - FLTK keys every Fl_Menu_Item off a single shared choice_cb()
//    plus a void* user_data holding the Fl_Color to apply (fl_voidptr()/
//    fl_uint() round-trip a color through a void*). Per CONVENTIONS.md's
//    callback convention this becomes plain D delegates that each just
//    capture the color value directly -- no void* round-trip needed.
//  - Choice/MenuItem, Fl_RGB_Image::color_average() (fl.image.RGBImage.
//    colorAverage()), and Window::icon() (fl.window.Window.icon()) are
//    all real, ported fldtk API, used directly below.
import fl;

DoubleWindow win;

void choiceCb(Color c)
{
    if (c != 0)
    {
        // choice was "Red", "Green"...
        static ubyte[32 * 32 * 3] buffer; // static: issue #296
        auto rgbicon = new RGBImage(buffer[], 32, 32, 3);
        rgbicon.colorAverage(c, 0.0f);
        win.icon(rgbicon); // once assigned, 'rgbicon' can go out of scope
    }
    else
    {
        // choice was "None"...
        win.icon(cast(RGBImage) null); // reset window icon
    }
}

MenuItem[] choices = [
    MenuItem("None", 0, (w) { choiceCb(cast(Color) 0); }, 0),
    MenuItem("Red", 0, (w) { choiceCb(red); }, 0),
    MenuItem("Green", 0, (w) { choiceCb(green); }, 0),
    MenuItem("Blue", 0, (w) { choiceCb(blue); }, 0),
    MenuItem(null, 0, null, 0),
];

void main(string[] args)
{
    auto window = new DoubleWindow(400, 300, "FLTK Window Icon Test");
    win = window;

    auto choice = new Choice(120, 100, 200, 25, "Window icon:");
    choice.menu(choices);
    choice.callback((w) { choiceCb(cast(Color) 0); });
    choice.when(whenRelease | whenNotChanged);
    choice.tooltip("Sets the application icon for window manager. "
                   ~ "Affects e.g. titlebar, toolbar, Dock, Alt-Tab..");

    window.end();
    window.show(args);
    choice.doCallback(); // make default take effect
    fl.run();
}
