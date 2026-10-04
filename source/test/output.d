// D transliteration of FLTK's test/output.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh output
import fl;

void main(string[] args)
{
    Output text;
    MultilineOutput text2;
    Input input;
    HorValueSlider fonts;
    HorValueSlider sizes;

    auto window = new Window(400, 400);

    input = new Input(50, 375, 350, 25);
    input.staticValue("The quick brown fox\njumped over\nthe lazy dog.");
    input.when(whenChanged);
    input.callback((w) {
        text.value(input.value());
        text2.value(input.value());
    });

    sizes = new HorValueSlider(50, 350, 350, 25, "Size");
    sizes.alignment(alignLeft);
    sizes.bounds(1, 64);
    sizes.step(1);
    sizes.value(14);
    sizes.callback((w) {
        text.textsize(cast(Fontsize) sizes.value());
        text.redraw();
        text2.textsize(cast(Fontsize) sizes.value());
        text2.redraw();
    });

    fonts = new HorValueSlider(50, 325, 350, 25, "Font");
    fonts.alignment(alignLeft);
    fonts.bounds(0, 15);
    fonts.step(1);
    fonts.value(0);
    fonts.callback((w) {
        text.textfont(cast(Font) fonts.value());
        text.redraw();
        text2.textfont(cast(Font) fonts.value());
        text2.redraw();
    });

    text2 = new MultilineOutput(100, 150, 200, 100, "MultilineOutput");
    text2.value(input.value());
    text2.alignment(alignBottom);
    text2.tooltip("This is a MultilineOutput widget.");
    window.resizable(text2);

    text = new Output(100, 90, 200, 30, "Output");
    text.value(input.value());
    text.alignment(alignBottom);
    text.tooltip("This is an Output widget.");

    window.end();
    window.show(args);
    fl.run();
}
