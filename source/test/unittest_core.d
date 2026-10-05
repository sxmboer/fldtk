// D transliteration of FLTK's test/unittest_core.cxx.
// One tab of the
// "unittests" bundle; see source/test/unittests.d for the registry
// (UnitTest) and the local Google-Test-alike (UtTest/UtSuite).
// Build: rdmd buildsamples.d test unittest_core
module unittest_core;

import fl;
import unittests;

/* Test additions to Preferences.
 *
 * FLTK registers this via the TEST(SUITE, CASE) macro; D has no
 * preprocessor macros, so the test is registered directly with a
 * delegate (see unittests.d's UtTest for why), and each EXPECT_STREQ()
 * macro invocation becomes a plain `if` calling UtSuite.logString().
 */
static this()
{
    new UtTest("Preferences", "Strings", {
        {
            auto prefs = new Preferences(rootUserL, "fltk.org", "unittests");
            prefs.set("a", "");
            prefs.set("b", "Hello");
            prefs.set("c", "Hel\\l\nö");
            // `~this()` only flushes to disk during GC finalization, which
            // has no guaranteed timing (see fl.preferences's own top
            // comment) -- flush() explicitly so the second Preferences
            // below reliably reads back what was just written, rather than
            // depending on the GC having collected this one by then.
            prefs.flush();
        }
        {
            auto prefs = new Preferences(rootUserL, "fltk.org", "unittests");
            string r;
            prefs.get("a", r, "x");
            if (r != "")
            {
                UtSuite.logString(__FILE__, __LINE__, "r", r, "\"\"");
                return false;
            }
            prefs.get("b", r, "x");
            if (r != "Hello")
            {
                UtSuite.logString(__FILE__, __LINE__, "r", r, "\"Hello\"");
                return false;
            }
            prefs.get("c", r, "x");
            if (r != "Hel\\l\nö")
            {
                UtSuite.logString(__FILE__, __LINE__, "r", r, "\"Hel\\\\l\\nö\"");
                return false;
            }
            prefs.get("d", r, "x");
            if (r != "x")
            {
                UtSuite.logString(__FILE__, __LINE__, "r", r, "\"x\"");
                return false;
            }
        }
        return true;
    });
}

//
//------- test aspects of the FLTK core library ----------
//

/*
 * Create a tab with only a terminal window in it. When shown for the
 * first time, unittest will visualize progress by running all
 * registered tests one-by-one every few milliseconds.
 *
 * When run in command line mode (option `--core`), all tests are
 * executed at full speed.
 */
class UtCoreTest : FlGroup
{
    private Terminal tty;
    private bool suiteRan_;

    // Create the tab
    static Widget create()
    {
        return new UtCoreTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    // Constructor for this tab
    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        tty = new Terminal(x + 4, y + 4, w - 8, h - 8, "Unittest Log");
        tty.ansi(true);
        end();
        UtSuite.tty = tty;
    }

    // Run one single test and repeat calling this until all tests are done
    private static void timerCb()
    {
        // Run a test every few milliseconds to visualize the progress
        if (UtSuite.runNextTest())
            fl.repeatTimeout(0.15, { timerCb(); });
    }

    // Showing this tab for the first time will trigger the tests
    override void show()
    {
        super.show();
        if (!suiteRan_)
        {
            fl.addTimeout(0.5, { timerCb(); });
            suiteRan_ = true;
        }
    }
}

// Register this tab with the unittest app.
static this()
{
    new UnitTest(UT_TEST_CORE, "Core Functionality", () => UtCoreTest.create());
}
