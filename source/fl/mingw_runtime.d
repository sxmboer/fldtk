/**
 * Runs the static constructors of MinGW-built C libraries linked into a
 * Windows D program.
 *
 * Not a port of an FLTK file -- infrastructure for the Windows Cairo and
 * Pango build (`version (FLDTK_HAVE_CAIRO)`/`version (FLDTK_HAVE_PANGO)`,
 * dub configuration `windows-cairo`), whose static libraries are built
 * with MSYS2's UCRT64 GCC and linked by dmd's lld-link in its MinGW mode
 * (`-lldmingw`, which GCC's C++ COMDAT sections in HarfBuzz and Pango
 * need) against the Universal C runtime.
 *
 * Several of those libraries initialize themselves in GCC
 * `__attribute__((constructor))` functions rather than on first use:
 * pixman selects its CPU-specific implementation that way (a pixman fill
 * before it runs dereferences a null implementation pointer), a static
 * GLib/GObject runs `glib_init()`/`gobject_init()` that way, and
 * libstdc++, libwinpthread and MinGW's stack protector set up their own
 * state. GCC targeting MinGW records each such function as a pointer in a
 * `.ctors` section, and MinGW's C runtime startup (`__main()`, which calls
 * `__do_global_ctors()`) calls them before `main()`. A D program starts
 * through the Microsoft-style C runtime startup in dmd's bundled
 * libraries instead, which runs only `.CRT$XC*` initializers, so nothing
 * calls the `.ctors` entries.
 *
 * This module's static constructor does that job. In MinGW mode lld-link
 * lays out the `.ctors` entries the way GNU ld's linker script does and
 * defines `__CTOR_LIST__` at their start: one word holding the entry
 * count, or -1 for "count until the terminating 0", then the function
 * pointers, then a 0 word. `runMingwConstructors()` walks that list
 * exactly as MinGW's `__do_global_ctors()` (`crt/gccmain.c`) does, from
 * the last entry to the first.
 *
 * `fl.cairo_c` and `fl.glib_c` import this module, so its constructor
 * runs before any D code that could call into those libraries -- D runs
 * an imported module's static constructors before the importing
 * module's. `__CTOR_LIST__` only exists in a MinGW-mode link, which is
 * what the `windows-cairo` configuration's lflags ask for; a link without
 * `-lldmingw` fails on it as an undefined symbol rather than producing a
 * program whose libraries were never initialized.
 *
 * `.dtors` (GCC `destructor` functions) are not run: the libraries
 * involved use them only to release process-lifetime state at exit.
 */
module fl.mingw_runtime;

version (Windows):

private alias Constructor = extern (C) void function() nothrow @nogc;

/// The start of the `.ctors` list, defined by lld-link in MinGW mode.
private extern (C) extern __gshared size_t __CTOR_LIST__;

shared static this()
{
    runMingwConstructors();
}

/// Calls every `.ctors` entry, last to first (see the module comment).
/// Runs once, from this module's static constructor; calling it again
/// does nothing.
void runMingwConstructors() nothrow @nogc
{
    __gshared bool done;
    if (done)
        return;
    done = true;

    size_t* list = &__CTOR_LIST__;
    size_t count = list[0];
    if (count == size_t.max)
    {
        count = 0;
        while (list[count + 1] != 0)
            count++;
    }
    foreach_reverse (i; 1 .. count + 1)
        (cast(Constructor) list[i])();
}
