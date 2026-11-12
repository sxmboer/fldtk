/*
 * Runs one process at a time for File > Run (`fluid.gui_main`): first
 * `dub build`, then the program it built. The process's output (stdout
 * and stderr together) is handed on as it arrives, read through
 * `fl.core.addFd()` so Fluid stays responsive, and `stop()` ends the
 * process.
 *
 * The process is started directly, not through a shell, so the pid
 * `stop()` kills is the process's own. `fluid.shell_process` is the
 * runner for the Shell menu's commands, which do go through a shell.
 *
 * A program writes its output to a pipe here, and the C library buffers
 * output to a pipe in blocks, so `writeln()` output would show only
 * when a block is full or the program ends. With `flushOutput`,
 * `runStart()` sets `FLDTK_FLUSH_OUTPUT` in the program's environment,
 * which makes a program built with fldtk write each line at once
 * (`fl.output_buffering`).
 */
module fluid.run_program;

import std.process;

import fl;
import fluid.dub_project : completeUtf8;

/// Receives each piece of output as it arrives; pieces end on a
/// character boundary, not necessarily on a line boundary.
void delegate(string text) onRunOutput;

private ProcessPipes pipes_;
private bool running_;
private bool stopped_;
private void delegate(int status, bool stopped) done_;
private char[] carry_;

/// Whether a process started by `start()` is still running.
bool runRunning() { return running_; }

/// Starts `args` (the program, then its arguments) in folder `workDir`.
/// `done` is called once the process has ended and its output has been
/// read, with its exit status (on Linux, minus the signal number when a
/// signal ended it), and whether `stop()` ended it. Returns false, after
/// reporting why through `onRunOutput`, when the process could not be
/// started; `done` is then not called. A process still running is
/// ended first (`runKill()`). `flushOutput` sets `FLDTK_FLUSH_OUTPUT`
/// for the process (see the module comment).
bool runStart(string[] args, string workDir, void delegate(int status, bool stopped) done, bool flushOutput = false)
{
    runKill();

    string[string] env;
    if (flushOutput) env["FLDTK_FLUSH_OUTPUT"] = "1";
    try
        pipes_ = pipeProcess(args, Redirect.stdout | Redirect.stderrToStdout, env, Config.none, workDir);
    catch (Exception e)
    {
        output("\033[1;31mCould not start " ~ args[0] ~ ": " ~ e.msg ~ "\033[0m\n");
        return false;
    }
    running_ = true;
    stopped_ = false;
    done_ = done;
    carry_ = null;
    fl.core.addFd(pipes_.stdout.fileno, (fd) { onReadable(fd); });
    return true;
}

/// Ends the running process, if any. Its `done` callback follows once
/// its output pipe closes.
void runStop()
{
    if (!running_) return;
    stopped_ = true;
    try kill(pipes_.pid);
    catch (Exception) {}
}

/// Ends the running process, if any, at once and waits for it, then
/// calls its `done` callback (stopped). On Linux it is killed outright
/// (`SIGKILL`), since this waits; `runStop()` asks it to end
/// (`SIGTERM`).
void runKill()
{
    if (!running_) return;
    stopped_ = true;
    try
    {
        version (Posix)
        {
            import core.sys.posix.signal : SIGKILL;
            kill(pipes_.pid, SIGKILL);
        }
        else
            kill(pipes_.pid);
    }
    catch (Exception) {}
    finish();
}

private void output(const(char)[] text)
{
    if (onRunOutput !is null && text.length)
        onRunOutput(text.idup);
}

private void onReadable(int fd)
{
    char[4096] buf;
    ptrdiff_t n = readSome(fd, buf[]);
    if (n < 0) return;
    if (n == 0)
    {
        finish();
        return;
    }
    const(char)[] data = carry_ ~ buf[0 .. n];
    const(char)[] rest;
    output(completeUtf8(data, rest));
    carry_ = rest.dup;
}

/// One read of what the pipe has, without waiting for more: the fd
/// callback only runs once the pipe is readable. Returns the number of
/// bytes read, 0 once the pipe is closed, or -1 when nothing is there.
private ptrdiff_t readSome(int fd, char[] buf)
{
    version (Posix)
    {
        import core.sys.posix.unistd : read;
        ptrdiff_t r = read(fd, buf.ptr, buf.length);
        return r < 0 ? 0 : r;
    }
    else version (Windows)
    {
        import core.stdc.stdio : _get_osfhandle;
        import core.sys.windows.windows : HANDLE, DWORD, PeekNamedPipe, ReadFile;

        HANDLE h = cast(HANDLE) _get_osfhandle(fd);
        DWORD avail;
        if (!PeekNamedPipe(h, null, 0, null, &avail, null)) return 0; // closed
        if (avail == 0) return -1;
        DWORD want = avail < buf.length ? avail : cast(DWORD) buf.length;
        DWORD got;
        if (!ReadFile(h, buf.ptr, want, &got, null)) return 0;
        return got;
    }
}

private void finish()
{
    fl.core.removeFd(pipes_.stdout.fileno);
    if (carry_.length) output(carry_);
    carry_ = null;
    int status;
    try status = wait(pipes_.pid);
    catch (Exception) status = -1;
    running_ = false;
    auto done = done_;
    done_ = null;
    if (done !is null) done(status, stopped_);
}
