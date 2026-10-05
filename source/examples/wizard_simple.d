// D transliteration of FLTK's examples/wizard-simple.cxx.
// Build: rdmd buildsamples.d examples wizard_simple
import fl;

//
// Simple 'wizard' using fldtk's Wizard widget
//
void main()
{
    auto win = new Window(400, 300, "Example Wizard");
    auto wiz = new Wizard(0, 0, 400, 300);

    // Wizard: page 1
    {
        auto g = new FlGroup(0, 0, 400, 300);
        auto next = new Button(290, 265, 100, 25, "Next @->");
        next.callback((w) { wiz.next(); });
        auto outp = new MultilineOutput(10, 30, 400 - 20, 300 - 80, "Welcome");
        outp.labelsize(20);
        outp.alignment(alignTop | alignLeft);
        outp.value("This is First page");
        g.end();
    }
    // Wizard: page 2
    {
        auto g = new FlGroup(0, 0, 400, 300);
        auto next = new Button(290, 265, 100, 25, "Next @->");
        next.callback((w) { wiz.next(); });
        auto back = new Button(180, 265, 100, 25, "@<- Back");
        back.callback((w) { wiz.prev(); });
        auto outp = new MultilineOutput(10, 30, 400 - 20, 300 - 80, "Terms And Conditions");
        outp.labelsize(20);
        outp.alignment(alignTop | alignLeft);
        outp.value("This is the Second page");
        g.end();
    }
    // Wizard: page 3
    {
        auto g = new FlGroup(0, 0, 400, 300);
        auto done = new Button(290, 265, 100, 25, "Finish");
        done.callback((w) { w.window().hide(); });
        auto back = new Button(180, 265, 100, 25, "@<- Back");
        back.callback((w) { wiz.prev(); });
        auto outp = new MultilineOutput(10, 30, 400 - 20, 300 - 80, "Finish");
        outp.labelsize(20);
        outp.alignment(alignTop | alignLeft);
        outp.value("This is the Last page");
        g.end();
    }
    wiz.end();
    win.end();
    win.show();
    fl.run();
}
