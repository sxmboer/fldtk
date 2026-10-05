// D transliteration of FLTK's examples/tabs-simple.cxx.
// Build: rdmd buildsamples.d examples tabs_simple
import fl;

//
// Simple tabs example
//      _____  _____
//   __/ Aaa \/ Bbb \______________________
//  |    _______                           |
//  |   |_______|                          |
//  |    _______                           |
//  |   |_______|                          |
//  |    _______                           |
//  |   |_______|                          |
//  |______________________________________|
//
void main()
{
    scheme("gtk+");
    auto win = new Window(500, 200, "Tabs Example");
    {
        // Create the tab widget
        auto tabs = new Tabs(10, 10, 500 - 20, 200 - 20);
        {
            // ADD THE "Aaa" TAB
            //   We do this by adding a child group to the tab widget.
            //   The child group's label defined the label of the tab.
            auto aaa = new FlGroup(10, 35, 500 - 20, 200 - 45, "Aaa");
            {
                // Put some different buttons into the group, which will be shown
                // when the tab is selected.
                auto b1 = new Button(50, 60, 90, 25, "Button A1");
                b1.color(88 + 1);
                auto b2 = new Button(50, 90, 90, 25, "Button A2");
                b2.color(88 + 2);
                auto b3 = new Button(50, 120, 90, 25, "Button A3");
                b3.color(88 + 3);
            }
            aaa.end();

            // ADD THE "Bbb" TAB
            //   Same details as above.
            auto bbb = new FlGroup(10, 35, 500 - 10, 200 - 35, "Bbb");
            {
                // Put some different buttons into the group, which will be shown
                // when the tab is selected.
                auto b1 = new Button(50, 60, 90, 25, "Button B1");
                b1.color(88 + 1);
                auto b2 = new Button(150, 60, 90, 25, "Button B2");
                b2.color(88 + 3);
                auto b3 = new Button(250, 60, 90, 25, "Button B3");
                b3.color(88 + 5);
                auto b4 = new Button(50, 90, 90, 25, "Button B4");
                b4.color(88 + 2);
                auto b5 = new Button(150, 90, 90, 25, "Button B5");
                b5.color(88 + 4);
                auto b6 = new Button(250, 90, 90, 25, "Button B6");
                b6.color(88 + 6);
            }
            bbb.end();
        }
        tabs.end();
    }
    win.end();
    win.show();
    fl.run();
}
