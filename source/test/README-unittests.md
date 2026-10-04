# How to add a new unittest tab

"unittests" here means the `build/unittests` GUI harness (a browsable
window of small, focused widget tests, one per tab) — not this
project's own `dub test` (Phobos `unittest {}` blocks in `source/fl/`).
See `README.md`'s "The `unittests` program" section for how the two
relate.

1. Create `source/test/unittest_xxx.d`. `unittest_points.d` is a good
   template to copy.

2. Define a class derived from `FlGroup` for your test, with a static
   `create()` factory:

   ```d
   module unittest_xxx;

   import fl;
   import unittests;

   class UtTestFoo : FlGroup
   {
       static Widget create()
       {
           return new UtTestFoo(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
       }

       this(int x, int y, int w, int h)
       {
           super(x, y, w, h);
           // ... build your test's widgets here ...
       }
   }

   static this()
   {
       new UnitTest(UT_TEST_FOO, "My foo tester", () => UtTestFoo.create());
   }
   ```

   Your test must do its work within the `UT_TESTAREA_X/Y/W/H` area
   (`unittests.d`), and must expect to be resized, though never smaller
   than that area.

3. Add an entry to the `enum : int { ... }` block near the top of
   `unittests.d`:

   ```d
   enum : int
   {
       UT_TEST_ABOUT = 0,
       ...
       UT_TEST_FOO,    // <- your new tab
   }
   ```

That's it — nothing else needs registering. Unlike FLTK (which
needs a `CMakeLists.txt` entry too), `buildsamples.d` already knows to
compile every `source/test/unittest_*.d` file into the `unittests`
binary regardless of import graph (see that script's own
`extraSources` table and `README.md`'s note on why these tabs are the
one case that needs it): a file matching that name pattern gets built
in automatically the next time you run `rdmd buildsamples.d test unittests`.

## General practices

Try to include documentation that briefly explains what the test does
and what to watch out for — if it won't fit in the test area itself,
add a "?" button or use a `tooltip()`.

## Why the registration mechanism looks the way it does

FLTK itself registers each tab via a file-scope global `UnitTest`
object — C++ runs a global's constructor before `main()` purely by
linking the translation unit in, no explicit call needed anywhere.
D has no equivalent of a *file*-scope object with a constructor, but it
does have `static this()` — a *module* constructor, the nearest D
equivalent of "runs before main(), just by being linked in" — which is
what each tab uses instead to call `new UnitTest(...)`. The `add()`
bookkeeping inside `UnitTest`'s own constructor (`unittests.d`) is
otherwise identical to FLTK's own.
