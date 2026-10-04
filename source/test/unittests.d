// D transliteration of FLTK's test/unittests.cxx + test/unittests.h
// (~/Repositories/fltk). Part of the samples/ contract -- see
// samples/README.md.
// Check: ./samples/build.sh unittests
//
// This is the "main()" translation unit of a 16-file bundle: the other
// 15 files (samples/test/unittest_*.d) are separate tabs that
// self-register into the `UnitTest` registry declared here, exactly the
// way each unittest_*.cxx FLTK self-registers a file-scope global
// `UnitTest` object into unittests.h's `UnitTest::test_list_[200]`. In D
// there is no file-scope object-with-constructor trick, so each tab
// module uses a `static this()` (a module constructor -- the nearest D
// equivalent of "runs before main(), just by being linked in") to call
// `new UnitTest(...)`, which still runs the same `add()` bookkeeping.
//
// `Ut_Test`/`Ut_Suite` and the TEST()/EXPECT_*() macros (unittests.h's
// "subset of the Google Test API") are also ported here since they're
// declared in unittests.h alongside UnitTest. D has no preprocessor
// macros, so instead of `TEST(SUITE, CASE) { ...; return true; }`
// expanding into a file-scope registration object, a test is registered
// directly: `new UtTest("SUITE", "CASE", { ...; return true; });`. The
// EXPECT_* macros become plain `if` statements calling UtSuite's log
// functions, inline in the test body (see unittest_core.d).
module unittests;

import fl;

// ----- WINDOW/WIDGET SIZES (unittests.h) -----
enum UT_MAINWIN_W = 700;
enum UT_MAINWIN_H = 600;
enum UT_BROWSER_X = 10;
enum UT_BROWSER_Y = 25;
enum UT_BROWSER_W = 150;
enum UT_BROWSER_H = UT_MAINWIN_H - 35;
enum UT_TESTAREA_X = UT_BROWSER_W + 20;
enum UT_TESTAREA_Y = 25;
enum UT_TESTAREA_W = UT_MAINWIN_W - UT_BROWSER_W - 30;
enum UT_TESTAREA_H = UT_BROWSER_H;

enum : int
{
    UT_TEST_ABOUT = 0,
    UT_TEST_POINTS,
    UT_TEST_FAST_SHAPES,
    UT_TEST_CIRCLES,
    UT_TEST_COMPLEX_SHAPES,
    UT_TEST_TEXT,
    UT_TEST_UNICODE,
    UT_TEST_SYBOL,
    UT_TEST_IMAGES,
    UT_TEST_VIEWPORT,
    UT_TEST_SCROLLBARSIZE,
    UT_TEST_SCHEMES,
    UT_TEST_SIMPLE_TERMINAL,
    UT_TEST_CORE
}

alias WidgetCreateFn = Widget delegate();

/// D port of unittests.h's `UnitTest` helper class -- registers a tab by
/// index, label, and a widget-factory delegate (FLTK: a raw
/// `Fl_Widget* (*create)()` function pointer; ported to a delegate per
/// CLAUDE.md's callback convention even though this particular one never
/// needs to close over state, just for consistency).
class UnitTest
{
    private static int numTests_;
    private static UnitTest[200] testList_;

    private string label_;
    private WidgetCreateFn create_;
    private Widget widget_;

    this(int index, string label, WidgetCreateFn create)
    {
        label_ = label;
        create_ = create;
        add(index, this);
    }

    string label() { return label_; }

    void create()
    {
        widget_ = create_();
        if (widget_ !is null)
            widget_.hide();
    }

    void show() { if (widget_ !is null) widget_.show(); }
    void hide() { if (widget_ !is null) widget_.hide(); }

    private static void add(int index, UnitTest t)
    {
        testList_[index] = t;
        if (index >= numTests_)
            numTests_ = index + 1;
    }

    static int numTests() { return numTests_; }
    static UnitTest test(int i) { return testList_[i]; }
}

// ----- Ut_Test / Ut_Suite: unittests.h's minimal Google-Test-alike -----

alias UtTestCall = bool delegate();

/// Ported from unittests.h's Ut_Test: a single test case, normally
/// created by the TEST(SUITE, CASE) macro FLTK. D has no
/// preprocessor, so callers construct one directly (see unittest_core.d).
class UtTest
{
    private string name_;
    private UtTestCall call_;
    private bool failed_;
    private bool done_;

    this(string suitename, string testname, UtTestCall call)
    {
        name_ = testname;
        call_ = call;
        failed_ = false;
        done_ = false;
        UtSuite suite = UtSuite.locate(suitename);
        suite.add(this);
    }

    /// Runs the test and returns false when it fails.
    bool run(string suite)
    {
        UtSuite.printf("%s[ RUN      ]%s %s.%s\n", UtSuite.green, UtSuite.normal, suite, name_);
        bool ret = call_();
        if (ret)
        {
            UtSuite.printf("%s[       OK ]%s %s.%s\n", UtSuite.green, UtSuite.normal, suite, name_);
            failed_ = false;
        }
        else
        {
            UtSuite.printf("%s[  FAILED  ]%s %s.%s\n", UtSuite.red, UtSuite.normal, suite, name_);
            failed_ = true;
        }
        done_ = true;
        return ret;
    }

    bool done() const { return done_; }

    void printFailed(string suite)
    {
        if (failed_)
            UtSuite.printf("%s[  FAILED  ]%s %s.%s\n", UtSuite.red, UtSuite.normal, suite, name_);
    }
}

/// Ported from unittests.h's Ut_Suite: groups Ut_Test instances by suite
/// name and drives running them (all at once, or one at a time for the
/// "Core Functionality" tab's animated progress -- see unittest_core.d).
class UtSuite
{
    private static UtSuite[] suiteList_;
    private static int numTests_;
    private static int numPassed_;
    private static int numFailed_;

    static string red = "\033[31m";
    static string green = "\033[32m";
    static string normal = "\033[0m";
    static Terminal tty;

    private UtTest[] testList_;
    private string name_;
    private bool done_;

    private this(string name)
    {
        name_ = name;
    }

    void add(UtTest test) { testList_ ~= test; }
    int size() { return cast(int) testList_.length; }

    static void color(int v)
    {
        if (v)
        {
            red = "\033[31m";
            green = "\033[32m";
            normal = "\033[0m";
        }
        else
        {
            red = "";
            green = "";
            normal = "";
        }
    }

    static UtSuite locate(string name)
    {
        foreach (s; suiteList_)
            if (s.name_ == name)
                return s;
        auto s = new UtSuite(name);
        suiteList_ ~= s;
        return s;
    }

    int run()
    {
        printSuiteEpilog();
        int numTestsFailed = 0;
        foreach (t; testList_)
            if (!t.run(name_))
                numTestsFailed++;
        return numTestsFailed;
    }

    void printSuiteEpilog()
    {
        printf("%s[----------]%s %d test%s from %s\n", green, normal,
            testList_.length, testList_.length == 1 ? "" : "s", name_);
    }

    void printFailed()
    {
        foreach (t; testList_)
            t.printFailed(name_);
    }

    static void printProlog()
    {
        numTests_ = 0;
        foreach (s; suiteList_)
            numTests_ += s.size();
        printf("%s[==========]%s Running %d tests from %d test case%s.\n",
            green, normal, numTests_, suiteList_.length, suiteList_.length == 1 ? "" : "s");
    }

    static void printEpilog()
    {
        printf("%s[==========]%s %d tests from %d test case%s ran.\n",
            green, normal, numTests_, suiteList_.length, suiteList_.length == 1 ? "" : "s");
        if (numPassed_)
            printf("%s[  PASSED  ]%s %d test%s.\n", green, normal, numPassed_, numPassed_ == 1 ? "" : "s");
        if (numFailed_)
            printf("%s[  FAILED  ]%s %d test%s, listed below:\n", red, normal, numFailed_, numFailed_ == 1 ? "" : "s");
        foreach (s; suiteList_)
            s.printFailed();
    }

    /// Runs every registered suite/test, returning the number failed.
    static int runAllTests()
    {
        printProlog();
        foreach (s; suiteList_)
        {
            int n = s.run();
            numPassed_ += s.size() - n;
            numFailed_ += n;
        }
        printEpilog();
        return numFailed_;
    }

    /// Runs a single not-yet-run test and returns true while more remain
    /// (used by unittest_core.d's animated "Core Functionality" tab).
    static bool runNextTest()
    {
        auto last = suiteList_[$ - 1];
        if (last.done_)
        {
            printEpilog();
            return false;
        }
        auto first = suiteList_[0];
        if (!first.done_ && !first.testList_[0].done())
            printProlog();
        foreach (st; suiteList_)
        {
            if (st.done_)
                continue;
            if (!st.testList_[0].done())
                st.printSuiteEpilog();
            foreach (t; st.testList_)
            {
                if (t.done())
                    continue;
                if (t.run(st.name_)) numPassed_++; else numFailed_++;
                return true;
            }
            st.done_ = true;
            return true;
        }
        return true;
    }

    /// A printf that is redirected to the terminal or stdout.
    static void printf(Args...)(string format, Args args)
    {
        import std.stdio : writef;
        if (tty !is null)
            tty.printf(format, args);
        else
            writef(format, args);
    }

    static void logBool(string file, int line, string cond, bool result, bool expected)
    {
        printf("%s(%d): error:\n", file, line);
        printf("Value of: %s\n", cond);
        printf("Actual:   %s\n", result ? "true" : "false");
        printf("Expected: %s\n", expected ? "true" : "false");
    }

    static void logString(string file, int line, string cond, string result, string expected)
    {
        printf("%s(%d): error:\n", file, line);
        printf("Value of: %s\n", cond);
        printf("  Actual: %s\n", result);
        printf("Expected: %s\n", expected);
    }

    static void logInt(string file, int line, string cond, int result, string expected)
    {
        printf("%s(%d): error:\n", file, line);
        printf("Value of: %s\n", cond);
        printf("  Actual: %d\n", result);
        printf("Expected: %s\n", expected);
    }

    static int failed() { return numFailed_; }
}

/// The main window needs an additional drawing feature in order to
/// support the viewport alignment test (Ut_Main_Window in unittests.h).
///
/// FLTK bases this on Fl_Double_Window; fldtk has no DoubleWindow
/// yet (only the plain single-buffered Window), so this deliberately
/// writes the call the way it should look once ported rather than
/// substituting today's Window.
class UtMainWindow : DoubleWindow
{
    private int drawAlignmentTest_;

    this(int w, int h, string l = null)
    {
        super(w, h, l);
    }

    void drawAlignmentIndicators()
    {
        enum SZE = 16;
        // top left corner
        fl_color(green); fl_yxline(0, SZE, 0, SZE);
        fl_color(red);   fl_yxline(-1, SZE, -1, SZE);
        fl_color(white); fl_rectf(3, 3, SZE - 2, SZE - 2);
        fl_color(black); fl_rect(3, 3, SZE - 2, SZE - 2);
        // bottom left corner
        fl_color(green); fl_yxline(0, h() - SZE - 1, h() - 1, SZE);
        fl_color(red);   fl_yxline(-1, h() - SZE - 1, h(), SZE);
        fl_color(white); fl_rectf(3, h() - SZE - 1, SZE - 2, SZE - 2);
        fl_color(black); fl_rect(3, h() - SZE - 1, SZE - 2, SZE - 2);
        // bottom right corner
        fl_color(green); fl_yxline(w() - 1, h() - SZE - 1, h() - 1, w() - SZE - 1);
        fl_color(red);   fl_yxline(w(), h() - SZE - 1, h(), w() - SZE - 1);
        fl_color(white); fl_rectf(w() - SZE - 1, h() - SZE - 1, SZE - 2, SZE - 2);
        fl_color(black); fl_rect(w() - SZE - 1, h() - SZE - 1, SZE - 2, SZE - 2);
        // top right corner
        fl_color(green); fl_yxline(w() - 1, SZE, 0, w() - SZE - 1);
        fl_color(red);   fl_yxline(w(), SZE, -1, w() - SZE - 1);
        fl_color(white); fl_rectf(w() - SZE - 1, 3, SZE - 2, SZE - 2);
        fl_color(black); fl_rect(w() - SZE - 1, 3, SZE - 2, SZE - 2);
    }

    override void draw()
    {
        super.draw();
        if (drawAlignmentTest_)
            drawAlignmentIndicators();
    }

    void testAlignment(int v)
    {
        drawAlignmentTest_ = v;
        redraw();
    }
}

UtMainWindow mainwin;
HoldBrowser browser;

// callback whenever the browser value changes
void uiBrowserCb(Widget)
{
    for (int t = 1; t <= browser.size(); t++)
    {
        UnitTest ti = cast(UnitTest) browser.data(t);
        if (browser.selected(t))
            ti.show();
        else
            ti.hide();
    }
}

private bool runCoreTestsOnly = false;

private int handleArg(string[] args, ref int i)
{
    if (args[i] == "--core")
    {
        runCoreTestsOnly = true;
        i++;
        return 1;
    }
    if (args[i] == "--color=0")
    {
        UtSuite.color(0);
        i++;
        return 1;
    }
    if (args[i] == "--color=1")
    {
        UtSuite.color(1);
        i++;
        return 1;
    }
    if (args[i] == "--help" || args[i] == "-h")
        return 0;
    return 0;
}

// This is the main call. It creates the window and adds all previously
// registered tests to the browser widget.
int main(string[] args)
{
    int i;
    fl.argsToUtf8(args); // for MSYS2/MinGW
    if (fl.args(args, i, (string[] a, ref int idx) => handleArg(a, idx)) == 0)
    {
        // unsupported argument found
        string appName = args.length > 0 ? filenameName(args[0]) : "unittests";
        if (appName.length == 0)
            appName = "unittests";
        import std.stdio : stderr;
        stderr.writefln(
            "usage: %s <switches>\n"
            ~ " --core : test core functionality only\n"
            ~ " --color=1, --color=0 : print test output in color or plain text"
            ~ " --help, -h : print this help page", appName);
        return 1;
    }

    if (runCoreTestsOnly)
        return UtSuite.runAllTests();

    fl.getSystemColors();
    scheme(scheme()); // init scheme before instantiating tests
    fl.visual(modeRgb);
    fl.useHighResGL(true);
    mainwin = new UtMainWindow(UT_MAINWIN_W, UT_MAINWIN_H, "fldtk Unit Tests");
    mainwin.sizeRange(UT_MAINWIN_W, UT_MAINWIN_H);
    browser = new HoldBrowser(UT_BROWSER_X, UT_BROWSER_Y, UT_BROWSER_W, UT_BROWSER_H, "Unit Tests");
    browser.alignment(alignTop | alignLeft);
    browser.when(whenChanged);
    browser.callback((w) { uiBrowserCb(w); });
    browser.linespacing(2);

    int n = UnitTest.numTests();
    for (i = 0; i < n; i++)
    {
        UnitTest t = UnitTest.test(i);
        if (t !is null)
        {
            mainwin.begin();
            t.create();
            mainwin.end();
            browser.add(t.label(), t);
        }
    }

    // Set a more appropriate color average for the "plastic" scheme
    // (since FLTK 1.5)
    plasticColorAverage(45);

    mainwin.resizable(mainwin);
    mainwin.show(args);
    // Select first test in browser, and show that test.
    browser.select(UT_TEST_ABOUT + 1);
    uiBrowserCb(browser);
    fl.run();
    return 0;
}
