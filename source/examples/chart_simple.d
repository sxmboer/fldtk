// D transliteration of FLTK's examples/chart-simple.cxx.
// Build: rdmd buildsamples.d examples chart_simple
import fl;
import std.math : sin;
import std.format : format;

// Globals
Window gWin;
Chart gChart;
Choice gChoice;

// Choice callback for changing chart type(), one per menu item -- each
// delegate below captures its own chart-type constant directly rather
// than stashing it in the menu item's void* user_data and reading it
// back via item->argument() (see CONVENTIONS.md's callback-delegate note,
// which calls out menu item callbacks by name).
void chartTypeCb(ubyte t)
{
    gChart.type(t);
    gChart.redraw();
}

void main()
{
    gWin = new Window(1000, 510, "Chart Simple");
    // Chart with a sin() wave of data
    gChart = new Chart(20, 20, gWin.w() - 40, gWin.h() - 80, "Chart");
    gChart.bounds(-125.0, 125.0);
    const double start = 1.5;
    const double end = start + 15.1;
    for (double t = start; t < end; t += 0.5)
    {
        double val = sin(t) * 125.0;
        string valStr = format("%.0f", val);
        gChart.add(val, valStr, (val < 0) ? red : green);
    }
    // Let user change chart type -- labels are the D-side
    // `fl.enumerations` constant spelling, not FLTK's C
    // `FL_*_CHART` macro names: this sample exists to teach a D
    // programmer which `fldtk` symbol to reach for, not to document
    // what the original C++ constant was called.
    gChoice = new Choice(140, 470, 200, 25, "Chart Type: ");
    gChoice.add("barChart", 0, (w) { chartTypeCb(barChart); });
    gChoice.add("horbarChart", 0, (w) { chartTypeCb(horbarChart); });
    gChoice.add("lineChart", 0, (w) { chartTypeCb(lineChart); });
    gChoice.add("fillChart", 0, (w) { chartTypeCb(fillChart); });
    gChoice.add("spikeChart", 0, (w) { chartTypeCb(spikeChart); });
    gChoice.add("pieChart", 0, (w) { chartTypeCb(pieChart); });
    gChoice.add("specialpieChart", 0, (w) { chartTypeCb(specialpieChart); });
    gChoice.value(0);
    gWin.resizable(gWin);
    gWin.show();
    fl.run();
}
