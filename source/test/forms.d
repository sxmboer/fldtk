// D transliteration of FLTK's test/forms.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh forms
//
// Another forms demo -- this is an XForms compatibility-layer program
// (FL/forms.H's fl_bgn_form()/fl_add_box()/... free-function API, a
// straight port of the old XForms library's API onto FLTK widgets).
// Kept as the legacy free-function API here rather than rewritten into
// modern widget construction -- see samples/README.md.
import fl;

int border = 1; // changed from FL_TRANSIENT for FLTK
// (this is so the close box and Esc work to close the window)

struct VNStruct
{
    Boxtype val;
    string name;
}

VNStruct[] btypes = [
    VNStruct(Boxtype.noBox, "no box"),
    VNStruct(Boxtype.upBox, "up box"),
    VNStruct(Boxtype.downBox, "down box"),
    VNStruct(Boxtype.borderBox, "border box"),
    VNStruct(Boxtype.shadowBox, "shadow box"),
    VNStruct(Boxtype.flatBox, "flat box"),
    VNStruct(Boxtype.engravedBox, "frame box"),
    VNStruct(Boxtype.embossedBox, "embossed box"),
    VNStruct(Boxtype.roundedBox, "rounded box"),
    VNStruct(Boxtype.rflatBox, "rflat box"),
    VNStruct(Boxtype.rshadowBox, "rshadow box"), // renamed for FLTK
    VNStruct(Boxtype.ovalBox, "oval box"),
    VNStruct(Boxtype.roundUpBox, "rounded3d upbox"),
    VNStruct(Boxtype.roundDownBox, "rounded3d downbox"),
    VNStruct(Boxtype.ovalBox, "oval3d upbox"),
    VNStruct(Boxtype.ovalBox, "oval3d downbox"),
    VNStruct(Boxtype.plasticUpBox, "plastic upbox"),
    VNStruct(Boxtype.plasticDownBox, "plastic downbox"),
    VNStruct(Boxtype.gtkUpBox, "GTK up box"),
    VNStruct(Boxtype.gtkRoundUpBox, "GTK round up box"),
    VNStruct(Boxtype.gleamUpBox, "Gleam up box"),
    /* sentinel */
    VNStruct(cast(Boxtype)(-1), null),
];

// pixmaps/sorceress.xbm data -- FLTK #includes a generated bitmap;
// not transliterated (binary asset, not FLTK API surface).
extern (C) int sorceressWidth, sorceressHeight;
extern (C) ubyte[] sorceressBits;

/*************** Callback **********************/

Window form;
Widget[18] tobj;
Widget exitob, btypeob, modeob;

void boxtypeCb(Widget ob)
{
    int reqBt = fl_get_choice(ob) - 1;
    static int lastbt = -1;

    if (lastbt != reqBt)
    {
        fl_freeze_form(form);
        fl_redraw_form(form);
        for (int i = 0; i < 18; i++)
            fl_set_object_boxtype(tobj[i], btypes[reqBt].val);
        fl_unfreeze_form(form);
        lastbt = reqBt;
        fl_redraw_form(form); // added for FLTK
    }
}

void modeCb(Widget)
{
    // empty
}

/*************** Creation Routines *********************/

void createFormForm()
{
    Widget obj;

    form = fl_bgn_form(Boxtype.noBox, 720, 520);
    obj = fl_add_box(Boxtype.upBox, 0, 0, 720, 520, "");
    fl_set_object_color(obj, blue, gray);
    obj = fl_add_box(Boxtype.downBox, 10, 90, 700, 420, "");
    fl_set_object_color(obj, gray, gray);
    obj = fl_add_box(Boxtype.downBox, 10, 10, 700, 70, "");
    fl_set_object_color(obj, cast(Color) 0 /* FL_SLATEBLUE */ , gray);
    tobj[0] = obj = fl_add_box(Boxtype.upBox, 30, 110, 110, 110, "Box");
    tobj[1] = obj = fl_add_text(normalText, 30, 240, 110, 30, "Text");
    tobj[2] = obj = fl_add_bitmap(normalBitmap, 40, 280, 90, 80, "Bitmap");
    fl_set_object_lcol(obj, blue);
    tobj[3] = obj = fl_add_chart(barChart, 160, 110, 160, 110, "Chart");
    tobj[4] = obj = fl_add_clock(analogClock, 40, 390, 90, 90, "Clock");
    // fl_set_object_dblbuffer(tobj[4], 1); // removed for FLTK
    tobj[5] = obj = fl_add_button(normalButton, 340, 110, 120, 30, "Button");
    tobj[6] = obj = fl_add_lightbutton(pushButton, 340, 150, 120, 30, "Lightbutton");
    tobj[7] = obj = fl_add_roundbutton(pushButton, 340, 190, 120, 30, "Roundbutton");
    tobj[8] = obj = fl_add_slider(vertSlider, 160, 250, 40, 230, "Slider");
    tobj[9] = obj = fl_add_valslider(vertSlider, 220, 250, 40, 230, "Valslider");
    tobj[10] = obj = fl_add_dial(lineDial, 280, 250, 100, 100, "Dial");
    tobj[11] = obj = fl_add_positioner(normalPositioner, 280, 380, 150, 100, "Positioner");
    tobj[12] = obj = fl_add_counter(normalCounter, 480, 110, 210, 30, "Counter");
    tobj[13] = obj = fl_add_input(normalInput, 520, 170, 170, 30, "Input");
    tobj[14] = obj = fl_add_menu(pushMenu, 400, 240, 100, 30, "Menu");
    tobj[15] = obj = fl_add_choice(normalChoice, 580, 250, 110, 30, "Choice");
    tobj[16] = obj = fl_add_timer(valueTimer, 580, 210, 110, 30, "Timer");
    // fl_set_object_dblbuffer(tobj[16], 1); // removed for FLTK
    tobj[17] = obj = fl_add_browser(normalBrowser, 450, 300, 240, 180, "Browser");
    exitob = obj = fl_add_button(normalButton, 590, 30, 100, 30, "Exit");
    btypeob = obj = fl_add_choice(normalChoice, 110, 30, 130, 30, "Boxtype");
    fl_set_object_callback(obj, (w) { boxtypeCb(w); });
    modeob = obj = fl_add_choice(normalChoice, 370, 30, 130, 30, "Graphics mode");
    fl_set_object_callback(obj, (w) { modeCb(w); });
    fl_end_form();
}

/*---------------------------------------*/

void createTheForms()
{
    createFormForm();
}

/*************** Main Routine ***********************/

string[] browserlines = [
    " ", "@C1@c@lbObjects Demo", " ",
    "This demo shows you all", "objects that currently",
    "exist in the Forms Library.", " ",
    "You can change the boxtype", "of the different objects",
    "using the buttons at the top", "of the form. Note that some",
    "combinations might not", "look too good. Also realize",
    "that for all object classes", "many different types are",
    "available with different", "behaviour.", " ",
    "With this demo you can also", "see the effect of the drawing",
    "mode on the appearance of", "the objects.",
];

void main(string[] args)
{
    Color c = black;

    fl_initialize(args, "FormDemo", null, 0);
    createTheForms();
    fl_set_bitmap_data(tobj[2], sorceressWidth, sorceressHeight, sorceressBits);
    fl_add_chart_value(tobj[3], 15, "item 1", c++);
    fl_add_chart_value(tobj[3], 5, "item 2", c++);
    fl_add_chart_value(tobj[3], -10, "item 3", c++);
    fl_add_chart_value(tobj[3], 25, "item 4", c++);
    fl_set_menu(tobj[14], "item 1|item 2|item 3|item 4|item 5");
    fl_addto_choice(tobj[15], "item 1");
    fl_addto_choice(tobj[15], "item 2");
    fl_addto_choice(tobj[15], "item 3");
    fl_addto_choice(tobj[15], "item 4");
    fl_addto_choice(tobj[15], "item 5");
    fl_set_timer(tobj[16], 1000.0);

    foreach (line; browserlines)
        fl_add_browser_line(tobj[17], line);

    foreach (vn; btypes)
    {
        if (cast(int) vn.val < 0)
            break;
        fl_addto_choice(btypeob, vn.name);
    }

    fl_show_form(form, placeMouse, border, "Box types");

    while (fl_do_forms() !is exitob)
    {
    }
}
