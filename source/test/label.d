// D transliteration of FLTK's test/label.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh label
import fl;

// pixmaps/blast.xpm, transcribed verbatim from the FLTK file.
immutable string[] blastXpm = [
    "32 32 32 1",
    " 	c #905518",
    ".	c #9F580E",
    "+	c #A36526",
    "@	c #AF6519",
    "#	c #BF7429",
    "$	c #C77622",
    "%	c #B67B3C",
    "&	c #D07518",
    "*	c #D88836",
    "=	c #E48628",
    "-	c #F28514",
    ";	c #FF951C",
    ">	c #FA9835",
    ",	c #FF982A",
    "'	c #F49F48",
    ")	c #FFA82D",
    "!	c #FFA93F",
    "~	c #FFBA1C",
    "{	c #FFB936",
    "]	c #FFBA4C",
    "^	c #FFCA42",
    "/	c #FFD329",
    "(	c #FFCF5E",
    "_	c #FFD94C",
    ":	c #FFE946",
    "<	c #FFFB3E",
    "[	c #FFFB55",
    "}	c #FEFC69",
    "|	c #FFFE82",
    "1	c #FFFFA3",
    "2	c #FEFFCB",
    "3	c #FEFFFC",
    "     % .  ....@@@#@@.+.+++%     ",
    "  %%++++.....@######@@@@.++ %   ",
    " %%% %++@@.@@@#$$#######@++++%% ",
    " %%+%+####@@$&&=*=&&$$####@++%%+",
    "+%+%#####&&&&&==='===*$$###%%%%+",
    "%+%%%%**=*&&&&>,>,>-=>==*$*##%%%",
    "  %#****'=>---,))!),>>>==***#%#+",
    "  @%*'''>>>>;;,{{{))))>>>''**#%+",
    " ..@#*'!]]]{)){^__^^{]!!!'''###+",
    " ..@$=']]((^^~~:::/__^{((!>**##@",
    "....&&=>(_|[::/<}[<[::_((!>==###",
    "....&&--!_}|}[<[}[}}}||_]!>>**##",
    "@@$$&&--;{:|1|[<|}|}||}_^]>>=*##",
    "##$$=-,;)~~<121<2|121}}:^])>=*$#",
    "#*'''!]{^_<<<1313332|}}}^{!>>*##",
    "%*'']((|}}||||<333321|[[_^]>==*#",
    "*''''((||112333333321|}[_^]!>=*#",
    "%%*''!]^_[[[}<13332}<[<:_])>>*$#",
    "##*==,,)~_:<[|212311}[</{),,=*$#",
    "#@$$==,;)~/<|1<2|<1}|[:^{)-=&&$@",
    ".@@$&&-;)~:|}<<1}[|}[[:^{,-=&$@@",
    "..@@&&-;)(}[/<[|[<<}<:_^{),=&$@.",
    "...@&&=,{_(~~:[[<</[[^~]!>>=&$@@",
    " .@@$&'!({;;{/}::/~/_^)),>=*$#@+",
    " ..@$=''>,-;)^__~^{)^]),,==*$#@@",
    ". @##*'==&--){({));;,{>>==$$#@++",
    "%++#%**$&&--,!));;;-->>=&$$##@+%",
    " +%%##@@@@&=>>>>>>=-==='$$#@@+++",
    " %%+@@..&.$&='==-&&&&&$*$#@@.+% ",
    " %%+ ....@$$*==&$&&&@$$##@@+ %  ",
    "   %  ....@#*#$$$#@@@@@##+@++   ",
    "        ..@####@@@@@..+@++%     "
];

Pixmap img;

ToggleButton imageb, imageovertextb, imagenexttotextb, imagebackdropb;
ToggleButton leftb, rightb, topb, bottomb, insideb, clipb, wrapb;
Box text;
Input input;
HorValueSlider fonts;
HorValueSlider sizes;
HorValueSlider hMargin, vMargin, imgSpacing;
DoubleWindow window;

void buttonCb(Widget)
{
    Align i = 0;
    if (leftb.value()) i |= alignLeft;
    if (rightb.value()) i |= alignRight;
    if (topb.value()) i |= alignTop;
    if (bottomb.value()) i |= alignBottom;
    if (insideb.value()) i |= alignInside;
    if (clipb.value()) i |= alignClip;
    if (wrapb.value()) i |= alignWrap;
    if (imageovertextb.value()) i |= alignTextOverImage;
    if (imagenexttotextb.value()) i |= alignImageNextToText;
    if (imagebackdropb.value()) i |= alignImageBackdrop;
    text.alignment(i);
    window.redraw();
}

void imageCb(Widget)
{
    if (imageb.value())
        text.image(img);
    else
        text.image(null);
    window.redraw();
}

void fontCb(Widget)
{
    text.labelfont(cast(Font) cast(int) fonts.value());
    window.redraw();
}

void hMarginCb(Widget)
{
    text.horizontalLabelMargin(cast(int) hMargin.value());
    window.redraw();
}

void vMarginCb(Widget)
{
    text.verticalLabelMargin(cast(int) vMargin.value());
    window.redraw();
}

void spacingCb(Widget)
{
    text.labelImageSpacing(cast(int) imgSpacing.value());
    window.redraw();
}

void sizeCb(Widget)
{
    text.labelsize(cast(int) sizes.value());
    window.redraw();
}

void inputCb(Widget)
{
    text.label(input.value());
    window.redraw();
}

void normalCb(Widget)
{
    text.labeltype(Labeltype.normalLabel);
    window.redraw();
}

void symbolCb(Widget)
{
    // FL_SYMBOL_LABEL is `#define FL_SYMBOL_LABEL FL_NORMAL_LABEL` FLTK
    // (Enumerations.H) -- a pure naming alias documenting that plain
    // FL_NORMAL_LABEL already draws "@"-prefixed symbol text, not a
    // distinct labeltype of its own. `Labeltype.freeLabeltype` is a
    // transliteration bug: it's the *unrelated* FL_FREE_LABELTYPE (the
    // starting index reserved for user-registered custom labeltypes via
    // Fl::set_labeltype()), which draws nothing here since nothing is
    // registered at that index -- this silently ate the arrow symbol
    // entirely.
    text.labeltype(Labeltype.normalLabel); // FL_SYMBOL_LABEL
    if (input.value()[0] != '@')
    {
        input.staticValue("@->");
        text.label("@->");
    }
    window.redraw();
}

void shadowCb(Widget)
{
    text.labeltype(Labeltype.shadowLabel);
    window.redraw();
}

void embossedCb(Widget)
{
    text.labeltype(Labeltype.embossedLabel);
    window.redraw();
}

void engravedCb(Widget)
{
    text.labeltype(Labeltype.engravedLabel);
    window.redraw();
}

// Labels use fldtk's own D spelling -- `Labeltype` is a closed enum, so
// shown qualified (`Labeltype.normalLabel`), matching what a D programmer
// actually types -- not FLTK's C `FL_*` macro name. See CLAUDE.md's
// memory notes on this standing rule for GUI text that names a constant.
MenuItem[] choices = [
    MenuItem("Labeltype.normalLabel", (w) { normalCb(w); }),
    MenuItem("Labeltype.normalLabel (symbol)", (w) { symbolCb(w); }),
    MenuItem("Labeltype.shadowLabel", (w) { shadowCb(w); }),
    MenuItem("Labeltype.engravedLabel", (w) { engravedCb(w); }),
    MenuItem("Labeltype.embossedLabel", (w) { embossedCb(w); }),
    MenuItem.init, // trailing null-text sentinel -- matches FLTK's
                   // own explicit `{0}` array terminator (test/label.cxx);
                   // fl.menu_popup's item-array walk is pointer-arithmetic-
                   // based (looks for MenuItem.text is null to know where
                   // the array ends), so dropping this reads past the
                   // array into whatever memory follows (SIGSEGV in
                   // fl.draw.detectSymbolsForMeasure() via a corrupted
                   // MenuItem.text).
];

void main(string[] args)
{
    img = new Pixmap(blastXpm);

    window = new DoubleWindow(440, 495);

    input = new Input(70, 435, 350, 25, "Label:");
    input.staticValue("The quick brown fox jumped over the lazy dog.");
    input.when(whenChanged);
    input.callback((w) { inputCb(w); });
    input.tooltip("label text");

    sizes = new HorValueSlider(70, 350, 350, 25, "Size:");
    sizes.alignment(alignLeft);
    sizes.bounds(1, 64);
    sizes.step(1);
    sizes.value(14);
    sizes.callback((w) { sizeCb(w); });

    fonts = new HorValueSlider(70, 325, 350, 25, "Font:");
    fonts.alignment(alignLeft);
    fonts.bounds(0, 15);
    fonts.step(1);
    fonts.value(0);
    fonts.callback((w) { fontCb(w); });

    auto margin = new Box(0, 380, 70, 25, "Margins");
    margin.box(Boxtype.flatBox);
    margin.alignment(alignRight | alignInside);

    hMargin = new HorValueSlider(70 + 50, 380, 125, 25, "Hor:");
    hMargin.alignment(alignLeft);
    hMargin.bounds(-25, 25);
    hMargin.step(1);
    hMargin.value(0);
    hMargin.callback((w) { hMarginCb(w); });

    vMargin = new HorValueSlider(70 + 175 + 50, 380, 125, 25, "Vert:");
    vMargin.alignment(alignLeft);
    vMargin.bounds(-25, 25);
    vMargin.step(1);
    vMargin.value(0);
    vMargin.callback((w) { vMarginCb(w); });

    imgSpacing = new HorValueSlider(70 + 50, 405, 125, 25, "Image:");
    imgSpacing.alignment(alignLeft);
    imgSpacing.bounds(0, 50);
    imgSpacing.step(1);
    imgSpacing.value(0);
    imgSpacing.callback((w) { spacingCb(w); });

    auto g = new FlGroup(70, 275, 350, 50);
    imageb = new ToggleButton(70, 275, 50, 25, "image");
    imageb.callback((w) { imageCb(w); });
    imageb.tooltip("show image");

    imageovertextb = new ToggleButton(120, 275, 50, 25, "T o I");
    imageovertextb.callback((w) { buttonCb(w); });
    imageovertextb.tooltip("alignTextOverImage");

    imagenexttotextb = new ToggleButton(170, 275, 50, 25, "I | T");
    imagenexttotextb.callback((w) { buttonCb(w); });
    imagenexttotextb.tooltip("alignImageNextToText");

    imagebackdropb = new ToggleButton(220, 275, 50, 25, "back");
    imagebackdropb.callback((w) { buttonCb(w); });
    imagebackdropb.tooltip("alignImageBackdrop");

    leftb = new ToggleButton(70, 300, 50, 25, "left");
    leftb.callback((w) { buttonCb(w); });
    leftb.tooltip("alignLeft");

    rightb = new ToggleButton(120, 300, 50, 25, "right");
    rightb.callback((w) { buttonCb(w); });
    rightb.tooltip("alignRight");

    topb = new ToggleButton(170, 300, 50, 25, "top");
    topb.callback((w) { buttonCb(w); });
    topb.tooltip("alignTop");

    bottomb = new ToggleButton(220, 300, 50, 25, "bottom");
    bottomb.callback((w) { buttonCb(w); });
    bottomb.tooltip("alignBottom");

    insideb = new ToggleButton(270, 300, 50, 25, "inside");
    insideb.callback((w) { buttonCb(w); });
    insideb.tooltip("alignInside");

    wrapb = new ToggleButton(320, 300, 50, 25, "wrap");
    wrapb.callback((w) { buttonCb(w); });
    wrapb.tooltip("alignWrap");

    clipb = new ToggleButton(370, 300, 50, 25, "clip");
    clipb.callback((w) { buttonCb(w); });
    clipb.tooltip("alignClip");

    g.resizable(insideb);
    g.end();

    auto c = new Choice(70, 250, 200, 25);
    c.menu(choices);

    text = new Box(Boxtype.engravedBox, 120, 75, 200, 100, input.value());
    text.alignment(alignCenter);

    window.resizable(text);
    window.end();
    window.show(args);
    fl.run();
}
