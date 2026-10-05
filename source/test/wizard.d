// D transliteration of FLTK's test/wizard.cxx.
// Build: rdmd buildsamples.d test wizard
import fl;
import fl.wizard : WizardBase = Wizard;

class Panel : FlGroup
{
    this(int x, int y, int w, int h, Color c, string t)
    {
        super(x, y, w, h, t);
        alignment(alignInside | alignCenter);
        box(Boxtype.engravedBox);
        labelcolor(c);
        labelsize(20);
        end();
    }
}

class Wizard : WizardBase
{
    private Panel p1, p2, p3;

    this(int x, int y, int w, int h, string t = null)
    {
        super(x, y, w, h, t);
        p1 = new Panel(x, y, w, h, red, "Panel 1");
        p2 = new Panel(x, y, w, h, magenta, "Panel 2");
        p3 = new Panel(x, y, w, h, blue, "Panel 3");
        value(p1);
    }

    void nextPanel()
    {
        Panel p = cast(Panel) value();
        if (p is p3) value(p1); else next();
    }

    void prevPanel()
    {
        Panel p = cast(Panel) value();
        if (p is p1) value(p3); else prev();
    }
}

void main(string[] args)
{
    auto window = new Window(300, 165, "Wizard test");
    auto wizard = new Wizard(5, 5, 290, 100);
    wizard.end();
    auto buttons = new FlGroup(5, 110, 290, 50);
    buttons.box(Boxtype.engravedBox);
    auto prevButton = new Button(15, 120, 110, 30, "@< Prev Panel");
    prevButton.callback((w) { wizard.prevPanel(); });
    prevButton.alignment(alignInside | alignCenter | alignLeft);
    auto nextButton = new Button(175, 120, 110, 30, "Next Panel @>");
    nextButton.alignment(alignInside | alignCenter | alignRight);
    nextButton.callback((w) { wizard.nextPanel(); });
    buttons.end();
    window.end();
    window.show(args);
    fl.run();
}
