// D transliteration of FLTK's test/iconize.cxx.
// Build: rdmd buildsamples.d test iconize
import fl;

void main(string[] args)
{
    auto mainw = new Window(200, 200);
    mainw.end();
    mainw.show(args);

    auto control = new Window(120, 120);

    auto hideButton = new Button(0, 0, 120, 30, "hide()");
    hideButton.callback((w) { mainw.hide(); });

    auto iconizeButton = new Button(0, 30, 120, 30, "iconize()");
    iconizeButton.callback((w) { mainw.iconize(); });

    auto showButton = new Button(0, 60, 120, 30, "show()");
    showButton.callback((w) { mainw.show(); });

    auto showButton2 = new Button(0, 90, 120, 30, "show this");
    showButton2.callback((w) { control.show(); });

    control.end();
    control.show();
    control.callback((w) { fl.hideAllWindows(); });
    fl.run();
}
