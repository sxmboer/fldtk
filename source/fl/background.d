/*
 * Work that runs in the background, so the window keeps drawing and
 * responding while it runs.
 *
 * A slow computation in a callback (reading a large file, a long
 * calculation) stops the window until it ends: it doesn't redraw, its
 * buttons don't respond, and the desktop may call the program "not
 * responding". `runInBackground()` runs the work on another thread and
 * hands its result to a second function on the GUI thread, where it is
 * safe to change widgets:
 *
 *     analyse.callback((w) {
 *         runInBackground({ return count(file); },       // another thread
 *                         (int n) { result.value(n); },  // the GUI thread
 *                         w);  // greyed out until the work is done
 *     });
 *
 * The work itself must not touch widgets: everything it needs goes in,
 * and everything it produces comes out as its return value. To show how
 * far it is, the work takes a `Report` and calls it, and the program
 * sets the `Job`'s `onProgress`:
 *
 *     auto job = runInBackground((Report report) {
 *                                    ...
 *                                    report(done / total);
 *                                    ...
 *                                },
 *                                (int n) { result.value(n); });
 *     job.onProgress = (fraction) { bar.value(fraction * 100); };
 *
 * Cancelling work that is running is not offered.
 */
module fl.background;

import core.atomic : atomicLoad, atomicStore;
import core.thread : Thread;
import core.time : MonoTime, msecs;
import fl.core : awake, awakeOnce, initThreads;
import fl.widget : Widget;

/// What work started by `runInBackground()` calls to say how far it is:
/// a fraction from 0 (just started) to 1 (done). It can be called as
/// often as is convenient; the GUI thread is told about the latest value
/// at most about 30 times a second.
alias Report = void delegate(double fraction);

/// A piece of work started by `runInBackground()`.
final class Job
{
    private bool running_ = true;
    private double progress_ = 0;      // the GUI thread's copy
    private shared double latest_ = 0; // written by the work's thread
    private MonoTime lastSent_;        // the work's thread only

    /// Called on the GUI thread with the fraction the work last reported.
    /// Set it right after `runInBackground()` returns, in the same
    /// callback: reports reach the GUI thread only once the callback has
    /// returned to the event loop, so none is missed.
    void delegate(double fraction) onProgress;

    /// Whether the work is still running; false from the moment its
    /// result is handed over (or its failure reported).
    bool running() const { return running_; }

    /// The fraction the work last reported, as far as the GUI thread
    /// knows: 0 until the first report.
    double progress() const { return progress_; }

    // The `Report` the work gets; runs on the work's thread. The value is
    // stored, and the GUI thread is woken to fetch it now and then. The
    // same delegate is sent each time, and `awakeOnce()` keeps only one
    // of them waiting, so the queue holds at most one per job.
    private void report(double fraction)
    {
        atomicStore(latest_, fraction);
        auto now = MonoTime.currTime;
        if (now - lastSent_ < 30.msecs) return;
        lastSent_ = now;
        awakeOnce(&deliver);
    }

    // Runs on the GUI thread.
    private void deliver()
    {
        double fraction = atomicLoad(latest_);
        if (fraction == progress_) return;
        progress_ = fraction;
        if (onProgress !is null) onProgress(fraction);
    }
}

/**
 * Runs `work` on another thread and, when it is done, calls `done` with
 * its result on the GUI thread. Returns at once, so it can be called
 * from a callback without stopping the window.
 *
 * With `busy` given (usually the button that started the work), that
 * widget is deactivated until the work is done, so the work can't be
 * started again while it runs. Without it, every click starts the work
 * once more; the returned `Job`'s `running` tells whether it is still
 * running.
 *
 * Work that takes a `Report` can say how far it is; see `Job.onProgress`.
 *
 * If the work throws, `done` is not called and the exception's message
 * is shown with `fl.ask.alert()`.
 */
Job runInBackground(T)(T delegate() work, void delegate(T) done, Widget busy = null)
    if (!is(T == void))
{
    return start(busy, (report, finish) {
        T result = work();
        finish(() { if (done !is null) done(result); });
    });
}

/// ditto, for work that reports its progress.
Job runInBackground(T)(T delegate(Report) work, void delegate(T) done, Widget busy = null)
    if (!is(T == void))
{
    return start(busy, (report, finish) {
        T result = work(report);
        finish(() { if (done !is null) done(result); });
    });
}

/// ditto, for work that returns nothing: `done`, if given, is called
/// when the work is done.
Job runInBackground(void delegate() work, void delegate() done = null, Widget busy = null)
{
    return start(busy, (report, finish) {
        work();
        finish(() { if (done !is null) done(); });
    });
}

/// ditto, for work that returns nothing and reports its progress.
Job runInBackground(void delegate(Report) work, void delegate() done = null, Widget busy = null)
{
    return start(busy, (report, finish) {
        work(report);
        finish(() { if (done !is null) done(); });
    });
}

// Starts `run` on a new thread. `run` does the work, reporting through
// `report`, and then calls `finish` with what is to happen on the GUI
// thread; `start` wraps that so the job is marked done, its last report
// handed over and `busy` given back first, and reports an exception
// from the work instead.
private Job start(Widget busy, void delegate(Report report, void delegate(void delegate()) finish) run)
{
    auto job = new Job;
    bool reactivate = busy !is null && busy.active();
    if (reactivate) busy.deactivate();

    void complete()
    {
        job.deliver();
        job.running_ = false;
        if (reactivate) busy.activate();
    }

    initThreads();
    auto thread = new Thread({
        try
        {
            run(&job.report, (void delegate() then) {
                awake(() { complete(); then(); });
            });
        }
        catch (Throwable e)
        {
            string msg = e.msg.idup;
            awake(() {
                import fl.ask : alert;
                complete();
                alert(msg);
            });
        }
    });
    thread.isDaemon = true; // a job still running doesn't keep the program alive
    thread.start();
    return job;
}

unittest
{
    import core.thread : Thread;
    import core.time : msecs;
    import fl.box : Box;
    import fl.core : drainAwakeQueue;
    import fl.group : FlGroup;

    // Waits for `job`, running the GUI-thread side as the event loop
    // would.
    void finish(Job job)
    {
        foreach (i; 0 .. 500)
        {
            drainAwakeQueue();
            if (!job.running) return;
            Thread.sleep(10.msecs);
        }
        assert(false, "the job never finished");
    }

    FlGroup.current(null);
    auto button = new Box(0, 0, 10, 10);

    // A result, handed over on this thread; the busy widget is inactive
    // while the work runs.
    import core.atomic : atomicLoad, atomicStore;
    int got;
    shared bool release;
    auto job = runInBackground({ while (!atomicLoad(release)) Thread.sleep(1.msecs); return 6 * 7; },
                               (int n) { got = n; }, button);
    assert(job.running && !button.active());
    atomicStore(release, true);
    finish(job);
    assert(got == 42 && button.active());

    // Work without a result, and without a busy widget.
    bool ran, told;
    job = runInBackground({ ran = true; }, { told = true; });
    finish(job);
    assert(ran && told);

    // A widget that was inactive before stays inactive.
    button.deactivate();
    job = runInBackground({ return "x"; }, (string s) {}, button);
    finish(job);
    assert(!button.active());

    // Progress: reports reach onProgress on this thread, the last one
    // before the result at the latest, and in order.
    double[] seen;
    job = runInBackground((Report report) {
        foreach (i; 1 .. 5)
        {
            report(i / 4.0);
            Thread.sleep(40.msecs);
        }
        return 0;
    }, (int n) {});
    job.onProgress = (fraction) { seen ~= fraction; };
    finish(job);
    assert(seen.length >= 1 && seen[$ - 1] == 1.0 && job.progress == 1.0);
    foreach (i; 1 .. seen.length) assert(seen[i] > seen[i - 1]);

    // Work without a result that reports.
    double last;
    job = runInBackground((Report report) { report(0.5); report(1); });
    job.onProgress = (fraction) { last = fraction; };
    finish(job);
    assert(last == 1);
}
