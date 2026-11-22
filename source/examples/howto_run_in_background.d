// Running slow work in the background with runInBackground(), so the
// window keeps drawing and responding while it runs, and showing how far
// the work is with a progress bar.
//
// The clock and the counter at the top run on timers: they stop whenever
// the window is frozen. Each button counts the prime numbers below twenty
// million, which takes several seconds:
//
//   - "Count"           runs in the background, with its progress bar
//                       below the buttons; the button is greyed out until
//                       the count is done, so it can't be started twice.
//   - "Count, repeated" runs in the background too, but every click starts
//                       another count, each with a progress bar of its own
//                       in the list at the bottom, which grows and shrinks.
//   - "Count, frozen"   counts inside the callback itself: the clock stops
//                       and the window doesn't respond until it is done.
//
// Build: rdmd buildsamples.d examples howto_run_in_background
import fl;
import std.format : format;

// The work: slow on purpose, and touching no widgets, since it runs on
// another thread. With a `report` given, it says how far it is now and
// then.
int countPrimes(int below, Report report = null)
{
    int count = below > 2 ? 1 : 0;
    for (int n = 3; n < below; n += 2)
    {
        bool prime = true;
        for (int d = 3; d * d <= n; d += 2)
            if (n % d == 0) { prime = false; break; }
        if (prime) count++;
        if (report !is null && n % 100_000 == 1)
            report(cast(double) n / below);
    }
    return count;
}

enum limit = 20_000_000;

void main()
{
    auto window = new DoubleWindow(420, 400, "Running in the background");

    // A clock widget: it ticks once a second on a timer of its own.
    new FlClock(roundClock, 10, 10, 70, 70, null);

    auto alive = new Box(90, 10, 320, 70);
    alive.labelsize(18);
    double seconds = 0;
    void tick()
    {
        seconds += 0.1;
        alive.copyLabel(format("The window is alive: %.1f s", seconds));
        repeatTimeout(0.1, &tick);
    }
    addTimeout(0.1, &tick);

    auto bar = new Progress(10, 130, 400, 20);
    auto result = new Output(10, 160, 400, 25);

    auto count = new Button(10, 90, 130, 30, "Count");
    count.tooltip("In the background; the button is greyed out until it is done");
    count.callback((w) {
        result.value("Counting...");
        auto job = runInBackground((Report report) { return countPrimes(limit, report); },
                                   (int n) { result.value(format("Count: %d primes", n)); },
                                   w);
        job.onProgress = (fraction) {
            bar.value(fraction * 100);
            bar.copyLabel(format("%.0f %%", fraction * 100));
        };
    });

    // The repeated counts: one progress bar each, stacked by a Pack (which
    // fits its height to them), inside a Scroll for when there are more
    // than fit.
    auto list = new Scroll(10, 215, 400, 175);
    list.box(Boxtype.downBox);
    list.alignment(alignTopLeft);
    auto rows = new Pack(12, 217, 380, 1);
    rows.spacing(2);
    rows.end();
    list.end();

    int started, running;
    void showRunning()
    {
        list.copyLabel(running == 0 ? "Repeated counts: none running"
                                    : format("Repeated counts: %d running", running));
        list.redraw();
    }
    showRunning();

    auto repeated = new Button(145, 90, 130, 30, "Count, repeated");
    repeated.tooltip("In the background; every click starts another count");
    repeated.callback((w) {
        int number = ++started;  // this count's own number, kept by its functions
        FlGroup.current(null);
        auto row = new Progress(0, 0, 380, 22);
        row.copyLabel(format("Count %d", number));
        rows.add(row);
        running++;
        showRunning();

        auto job = runInBackground((Report report) { return countPrimes(limit, report); },
                                   (int n) {
                                       rows.remove(row);
                                       running--;
                                       showRunning();
                                       result.value(format("Count %d: %d primes", number, n));
                                   });
        job.onProgress = (fraction) {
            row.value(fraction * 100);
            row.copyLabel(format("Count %d: %.0f %%", number, fraction * 100));
        };
    });

    auto frozen = new Button(280, 90, 130, 30, "Count, frozen");
    frozen.tooltip("In the callback itself: the window freezes until it is done");
    frozen.callback((w) {
        result.value(format("Count, frozen: %d primes", countPrimes(limit)));
    });

    window.end();
    window.show();
    run();
}
