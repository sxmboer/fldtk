// D transliteration of FLTK's test/threads.cxx + test/threads.h.
// Build: rdmd buildsamples.d test threads
//
// Notes on this transliteration:
//  - threads.h exists purely so FLTK's *demo* programs can spawn a
//    thread portably; it #ifdef-selects pthreads/Win32/Watcom. Per the
//    batch instructions, Linux/pthread is this project's primary target
//    (CONVENTIONS.md), so only that branch matters -- same approach
//    source/test/sudoku.d took picking ALSA over CoreAudio/Win32/X11-bell.
//    Rather than transliterate threads.h's `Fl_Thread`
//    typedef/`fl_create_thread()` wrapper around a raw
//    `pthread_create(..., Fl_Thread_Func*, void*)`, this file uses D's
//    own `core.thread.Thread` directly (the batch instructions call this
//    out explicitly as the natural D analogue of raw pthread_create).
//    That also means `prime_func`'s `void*` "which terminal" argument
//    disappears: each thread's Thread delegate just closes over the
//    Terminal/Output it should use, the same function-pointer+void*
//    -> capturing-delegate substitution CONVENTIONS.md documents for
//    Fl_Widget callbacks, applied here to Fl_Awake_Handler and
//    fl_create_thread's Fl_Thread_Func alike.
//  - Fl_Terminal is `fl.terminal.Terminal` (a real, complete port --
//    see that module's PORTING.md row), used here as-is.
//  - Fl::lock()/Fl::unlock()/Fl::awake()/Fl::awake(handler, data)/
//    Fl::now()/Fl::seconds_since() are real, ported fl.core API (see
//    that module's "Thread locking" section comment). `awake(handler,
//    data)` became `awake(AwakeHandler)`, dropping the Fl_Awake_Handler
//    function-pointer+void* pair for a single capturing delegate, the
//    usual substitution.
//  - A real, D-specific gotcha hit while getting this sample working:
//    module-level variables (`tty1`/`tty2`/`value1`/`value2`/`start2`
//    below) are thread-local by default in D, unlike C++ where a plain
//    global is implicitly shared across every thread -- marked
//    `__gshared` to restore FLTK's actual sharing semantics (the
//    worker threads below read them). Without this, every worker
//    thread saw its own null `tty1`/`tty2` copies, so `terminal is
//    tty2` was comparing `null is null` (always true) instead of
//    identifying which window's thread it actually was.
import fl;
import core.thread : Thread;
import std.math : sqrt;
import std.format : format;
import std.stdio : writefln;

// min. time in seconds before calling fl.awake(...)
enum double DELTA = 0.25;

// struct to collect primes until at least <DELTA> seconds passed.
// Two such structs per thread are used as alternate buffers.
struct Prime
{
    int idx;                 // thread index: 0 or {1..6}
    bool done;                // set to true after it was worked on
    Terminal terminal;        // widget to write output to
    ulong maxPrime;           // highest prime found so far
    Output value;              // highest prime output widget
    ulong[] primes;            // collected primes within time frame
}

// D module-level variables are thread-local by default (unlike C++,
// where a plain global is implicitly shared across threads) -- __gshared
// opts these back into FLTK's actual sharing semantics, needed since
// the worker threads below read tty1/tty2/value1/value2 (written once in
// main() before any thread starts) and read-modify-write start2 (guarded
// by fl.lock()/fl.unlock(), matching FLTK's own comment on why).
__gshared Terminal tty1, tty2;
__gshared Output value1, value2;
__gshared int start2 = 3;

void magicNumberCb(Output w)
{
    w.labelcolor(red);
    w.parent.redraw();
    // if (w is value1) fl.hideAllWindows(); // TEST: terminate early to measure time
}

// This is called indirectly by fl.awake(() { updateHandler(pr); }) in
// the context of the main (FLTK GUI) thread.
void updateHandler(Prime* pr)
{
    foreach (n; pr.primes)
    {
        pr.terminal.printf("prime: %10u\n", n);
        if (n > pr.maxPrime) pr.maxPrime = n;
    }
    pr.value.value(format("%9u", pr.maxPrime));
    pr.done = true;
}

void primeFunc(Terminal terminal)
{
    Output value;
    ulong n;
    ulong maxValue = 0;
    int step;
    bool proud = false;

    // initialize thread variables

    if (terminal is tty2)
    {
        // multiple threads
        fl.lock();          // lock to prevent race condition on `start2`
        n = start2;
        start2 += 2;
        fl.unlock();
        step = 12;
        value = value2;
    }
    else
    {
        // single thread
        n = 3;
        step = 2;
        value = value1;
    }

    // initialize alternate buffers (Prime) to store primes

    Prime[2] pr;
    pr[0].idx = pr[1].idx = (cast(int) n / 2 - 1);
    pr[0].done = false;
    pr[1].done = true;
    pr[0].terminal = pr[1].terminal = terminal;
    pr[0].maxPrime = pr[1].maxPrime = 0;
    pr[0].value = pr[1].value = value;
    pr[0].primes = [];
    pr[1].primes = [];
    int pi = 0; // prime buffer index

    Timestamp last = fl.now();

    // very simple prime number calculator!
    for (;;)
    {
        int pp;
        int hn = cast(int) sqrt(cast(double) n);

        for (pp = 3; pp <= hn; pp += 2)
        {
            if (n % pp == 0) break;
        }

        if (pp > hn)
        {
            // n is a prime
            pr[pi].primes ~= n;

            // Send a message to the main thread, at which point it will
            // process any pending updates.

            double ssl = fl.secondsSince(last);

            if (ssl > DELTA && pr[1 - pi].done)
            {
                // ready to switch buffers
                last = fl.now();
                auto prp = &pr[pi];
                fl.awake(() { updateHandler(prp); });
                pi = 1 - pi;         // switch to alternate buffer
                pr[pi].primes = [];  // clear primes
            }

            if (n > maxValue) pr[pi].maxPrime = n;

            n += step;

            if (n > 5 * 1000 * 1000 && !proud)
            {
                proud = true;
                auto valuep = value;
                fl.awake(() { magicNumberCb(valuep); });
            }
        }
        else
        {
            // This should not be necessary since "n" and "step" are local
            // variables, however it appears that at least MacOS X has some
            // threading issues that cause semi-random corruption of the
            // (stack) variables.
            fl.lock();
            n += step;
            fl.unlock();
        }
    }
}

// close all windows when the user closes one of the windows
void closeCb(Widget)
{
    fl.hideAllWindows();
    writefln("Max prime number with 1 thread : %s", value1.value());
    writefln("Max prime number with 6 threads: %s", value2.value());
}

void main(string[] args)
{
    // First window: single thread
    auto w1 = new DoubleWindow(200, 200, "Single Thread");
    tty1 = new Terminal(0, 0, 200, 175);
    tty1.color(background2Color);
    tty1.textcolor(foregroundColor);
    w1.resizable(tty1);
    value1 = new Output(100, 175, 98, 23, "Max Prime:");
    value1.textfont(courier);
    w1.callback((w) { closeCb(w); });
    w1.end();
    w1.show(args);

    // Second window: multiple threads
    auto w2 = new DoubleWindow(200, 200, "Six Threads");
    tty2 = new Terminal(0, 0, 200, 175);
    tty2.color(background2Color);
    tty2.textcolor(foregroundColor);
    w2.resizable(tty2);
    value2 = new Output(100, 175, 98, 23, "Max Prime:");
    value2.textfont(courier);
    w2.callback((w) { closeCb(w); });
    w2.end();
    w2.show();

    tty1.printf("Prime numbers:\n");
    tty2.printf("Prime numbers:\n");

    // Enable multi-thread support by locking from the main thread.
    // fl.wait()/fl.run() call fl.unlock()/fl.lock() as needed
    // to release control to the child threads when it is safe to do so...

    fl.lock();

    // Start threads...

    // One thread displaying in one terminal
    spawnPrimeThread(tty1);

    // Six threads displaying in another terminal
    spawnPrimeThread(tty2);
    spawnPrimeThread(tty2);
    spawnPrimeThread(tty2);
    spawnPrimeThread(tty2);
    spawnPrimeThread(tty2);
    spawnPrimeThread(tty2);

    fl.run();
}

// primeFunc() never returns (matching FLTK's own prime_func(),
// whose own comment notes "the return... can never be reached") -- in
// the transliterated C++, that's harmless: main() returning calls
// exit(), which kills every thread immediately regardless of join
// state. D has no equivalent for a plain core.thread.Thread: druntime's
// shutdown path (thread_joinAll(), run after main() returns) blocks
// waiting for every *non-daemon* thread to finish first, so without
// isDaemon = true here the process would hang forever after both
// windows close. Marking these threads daemons opts them out of that
// join, restoring FLTK's actual "process exit kills everything"
// behavior.
void spawnPrimeThread(Terminal terminal)
{
    auto t = new Thread(() { primeFunc(terminal); });
    t.isDaemon = true;
    t.start();
}
