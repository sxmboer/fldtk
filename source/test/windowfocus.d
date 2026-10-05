// D transliteration of FLTK's test/windowfocus.cxx.
// Build: rdmd buildsamples.d test windowfocus
import fl;

private DoubleWindow win1, win2;
private Input input1;

private void popup(Widget w)
{
    win2.position(win1.x() + win1.w(), win1.y());

    win2.show();
    win2.waitForExpose();
    input1.takeFocus();
}

void main(string[] args)
{
    win1 = new DoubleWindow(300, 200);
    win1.label("show() focus test");

    auto b = new Box(10, 10, 280, 130);
    b.label("Type something to open a 2nd window. "
        ~ "The focus should stay on the input, "
        ~ "and you should be able to continue typing.");
    b.alignment(alignWrap | alignLeft | alignInside);

    input1 = new Input(10, 150, 150, 25);
    input1.when(whenChanged);
    input1.callback((w) { popup(w); });

    win1.end();

    win2 = new DoubleWindow(300, 200);
    win2.label("window2");
    win2.end();

    win1.show(args);

    fl.run();
}
