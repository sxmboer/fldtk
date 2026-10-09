/**
 * Launches and tracks an external text editor for a code block,
 * reloading the block's own text once the editor's own save touches
 * the temp file on disk -- ported from FLTK's
 * `fluid/tools/ExternalCodeEditor_UNIX.h`/`.cxx` (Unix only FLTK
 * too; `ExternalCodeEditor_WIN32.h`/`.cxx` is Windows-specific and out
 * of scope, matching this project's Linux/Wayland-primary platform
 * scope).
 *
 * **`std.process`/`std.file` replace FLTK's raw `fork()`/
 * `execvp()`/`waitpid()`/`pipe()`/`stat()`/`mkdir()` entirely** (per
 * CONVENTIONS.md's "check for a cleaner D stdlib alternative before
 * transliterating a raw C library call" convention) -- this isn't a
 * marginal cleanup, it eliminates whole subsystems FLTK needs
 * purely because C++ has no safe process-spawning primitive:
 *
 *  - `std.process.spawnProcess()` throws a `ProcessException`
 *    *synchronously*, in the parent, the moment the executable can't
 *    be found/exec'd. FLTK's own `fork()`+`execvp()` can't do
 *    this -- a failed `execvp()` happens in the *child*, after the
 *    fork, with no safe way to call back into the FLTK/GUI-using
 *    parent -- so it built a whole self-pipe mechanism instead
 *    (`alert_pipe_`/`open_alert_pipe()`/`alert_pipe_cb()`: open a
 *    pipe before forking, write the child's `errno` into it if
 *    `execvp()` fails, and have the parent's event loop poll that fd
 *    via `Fl::add_fd()` to notice and show the resulting `fl_alert()`).
 *    None of that exists here -- `openEditor()` just catches
 *    `ProcessException` and reports it directly.
 *  - `std.process.spawnProcess(string[] args)` takes a real argv
 *    array, so FLTK's own `make_args()` (hand-rolled `strtok()`-
 *    based command-line splitting into a `malloc()`'d `argv[]`) is
 *    just `commandLine.split()` here (`std.string.split`, whitespace-
 *    delimited, matching `strtok(s, " \t")`'s own delimiter set).
 *  - `std.file.exists()`/`.isFile()`/`.isDir()`/`.mkdir()`/`.rmdir()`/
 *    `.timeLastModified()`/`.getSize()`/`.write()`/`.read()` replace
 *    every `stat()`/`open()`/`read()`/`write()`/`close()` call
 *    FLTK needs for temp-file/temp-dir bookkeeping.
 *  - `std.process.tryWait()`/`.kill()`/`.wait()` replace
 *    `waitpid(WNOHANG)`/`kill(pid, SIGTERM)`/the blocking reap loop.
 *
 * Also not ported: `Fluid.debug_external_editor`-gated `printf()`
 * tracing throughout FLTK's own file -- internal debug scaffolding
 * with no functional effect, matching this project's usual practice
 * of not porting FLTK's own debug-print statements.
 *
 * **Temp file extension**: FLTK's `tmp_filename()` uses `Fluid.
 * proj.code_file_name` (a per-project-configurable C++ source
 * extension, e.g. `.cxx`) -- this dialect has no such setting (single-
 * file `.d` output only, no header/`.cxx` split, see `PORTING.md`'s
 * `## Fluid` section intro), so the temp file extension is hardcoded
 * to `.d` instead, matching every other generated-file convention in
 * this port.
 *
 * The UI is wired up: `widget_panel.fl`'s Code
 * page has its own "Edit Externally..." button (`codeEditExternallyBtn`,
 * next to `codeText`), calling `onOpenExternalEditor(currentCodeNode_)`
 * -- which `gui_main.d`'s `make_widget_panel()` wiring points
 * at a real `openExternalEditor(n)` call. Both the plumbing and its one
 * call site are real, end to end.
 */
module fluid.external_code_editor;

import core.memory : GC;
import std.process : spawnProcess, Pid, tryWait, kill, wait, ProcessException;
import std.file : exists, isFile, isDir, mkdir, rmdir, remove, timeLastModified,
    getSize, write, read;
import std.datetime : SysTime;
import std.string : split;
import std.format : format;
import std.path : buildPath;
import std.conv : to;
import core.thread : Thread;
import core.time : msecs;

import fl.ask : alert, choice;
import fl.core : addTimeout, removeTimeout, TimeoutHandler;

private int editorsOpen_;
private TimeoutHandler updateTimerCb_;

class ExternalCodeEditor
{
    private Pid pid_;
    private bool running_;
    private SysTime fileMtime_;
    private ulong fileSize_;
    private string filename_;
    private string commandLine_;

    ~this()
    {
        // GC-finalizer hazard (CONVENTIONS.md's own established note):
        // closeEditor() can pop `fl_alert()`/`fl_choice()` dialogs and
        // touch `fl.core`'s timer queue, both cross-object GC-managed
        // state only safe to touch outside of finalization. Skipped
        // during a GC sweep -- if the collector reclaimed this object,
        // nothing reachable was still pointing at its (possibly still
        // running) editor process either; an explicit `destroy()`
        // (or simply calling `closeEditor()` yourself before letting
        // the object go) is the deterministic path this needs.
        if (GC.inFinalizer())
            return;
        closeEditor();
        filename_ = null;
    }

    /// Is the editor currently running?
    bool isEditing() const { return running_; }

    /// The temp file currently being edited, or `null`.
    string filename() const { return filename_; }

    /// Waits for the editor to close, prompting the user to close it
    /// (or force-close it) if it's still running.
    void closeEditor()
    {
        while (isEditing())
        {
            int reaped = reapEditor();
            if (reaped == -2) // no editor running (shouldn't happen -- isEditing() just checked)
                return;
            if (reaped == 1) // reaped
                return;
            if (reaped == -1)
            {
                alert(format("Error reaping external editor\npid=%d file=%s", pid_.processID, filename_));
                continue;
            }
            // Still running (reaped == 0): ask the user.
            int c = choice(
                format("Please close external editor\npid=%d file=%s", pid_.processID, filename_),
                "Force Close", "Closed", null);
            if (c == 0)
                killEditor();
            // c == 1 ("Closed"): loop back around and try reaping again.
        }
    }

    /// Kills the editor (if running) and waits for it to actually exit.
    void killEditor()
    {
        if (!isEditing()) return;
        try
            kill(pid_);
        catch (Exception e)
        {
            // Matches FLTK's own `kill(pid_, SIGTERM)` -- a raw
            // syscall whose return value isn't even checked there;
            // this port's `std.process.kill()` can throw for the same
            // "already gone" cases the syscall would just silently
            // report via errno, so the same "don't care" tolerance
            // applies here, just spelled as a caught exception.
        }
        int wcount;
        while (isEditing())
        {
            Thread.sleep(100.msecs);
            int reaped = reapEditor();
            if (reaped == -2)
                return;
            if (reaped == 1)
                return;
            if (reaped == -1)
            {
                alert(format("Can't seem to close editor of file: %s\nwaiting on it failed\nPlease close editor and hit OK", filename_));
                continue;
            }
            if (++wcount > 30) // ~3 seconds of retrying
                alert(format("Can't seem to close editor of file: %s\nPlease close editor and hit OK", filename_));
        }
    }

    /// Checks whether the edited file changed since the last check (or
    /// since `openEditor()`), reloading it if so. `force` reloads
    /// unconditionally.
    ///
    /// Returns 1 with `code` set if the file changed and was reloaded,
    /// 0 if unchanged (or not editing) -- `code` untouched -- or -1 on
    /// a read error (a dialog is shown with the reason).
    int handleChanges(out string code, bool force = false)
    {
        if (!isEditing()) return 0;

        bool changed;
        try
        {
            SysTime nowMtime = timeLastModified(filename_);
            ulong nowSize = getSize(filename_);
            if (nowMtime != fileMtime_) { changed = true; fileMtime_ = nowMtime; }
            if (nowSize != fileSize_) { changed = true; fileSize_ = nowSize; }
        }
        catch (Exception e)
        {
            return -1;
        }

        if (!changed && !force) return 0;

        try
        {
            code = cast(string) read(filename_);
            return 1;
        }
        catch (Exception e)
        {
            alert(format("ERROR: can't read '%s': %s", filename_, e.msg));
            return -1;
        }
    }

    /// Removes the temp file (if any) and clears the filename/mtime/
    /// size records. Returns 1 if a file was removed, 0 if there was
    /// none, -1 on error (a dialog is shown with the reason).
    int removeTmpfile()
    {
        if (filename_ is null) return 0;
        if (exists(filename_) && isFile(filename_))
        {
            try
                remove(filename_);
            catch (Exception e)
            {
                alert(format("WARNING: can't remove '%s': %s", filename_, e.msg));
                return -1;
            }
        }
        filename_ = null;
        fileMtime_ = SysTime.init;
        fileSize_ = 0;
        return 1;
    }

    /// Opens `code` (may be empty) in `editorCmd` (a shell-style
    /// command, e.g. `"gedit --wait"` -- the temp filename is appended
    /// as its own final argument, split the same whitespace-delimited
    /// way `std.string.split()` always does, matching FLTK's own
    /// `strtok(s, " \t")`). Returns 0 on success, -1 on error (a
    /// dialog is shown with the reason) or if an editor is already
    /// open on this same instance.
    int openEditor(string editorCmd, string code)
    {
        if (filename_ is null)
        {
            filename_ = tmpFilename();
            if (filename_ is null) return -1;
        }

        if (exists(filename_) && isFile(filename_) && isEditing())
        {
            int reaped = reapEditor();
            if (reaped == 0) // still running
            {
                alert(format("Editor Already Open\n  file='%s'\n  pid=%d", filename_, pid_.processID));
                return 0;
            }
            else if (reaped == -1)
            {
                alert(format("ERROR: waitpid()-equivalent failed for '%s', pid=%d", filename_, pid_.processID));
                return -1;
            }
            // reaped == 1 or -2: fall through to reopen with a fresh temp filename.
            filename_ = tmpFilename();
        }

        try
            write(filename_, code is null ? "" : code);
        catch (Exception e)
        {
            alert(format("ERROR: can't write '%s': %s", filename_, e.msg));
            return -1;
        }

        try
        {
            fileMtime_ = timeLastModified(filename_);
            fileSize_ = getSize(filename_);
        }
        catch (Exception e)
        {
            alert(format("ERROR: can't stat '%s': %s", filename_, e.msg));
            return -1;
        }

        return startEditor(editorCmd, filename_);
    }

    /// Non-blocking check for whether the editor process has exited --
    /// public, matching FLTK, since the app's own periodic polling
    /// callback (see `setUpdateTimerCallback()`) is expected to call
    /// this directly, alongside `handleChanges()`, for every open
    /// editor. Returns -2 if no editor is running, -1 if waiting on it
    /// failed, 0 if it's still running, or 1 if it just exited (the temp
    /// file is removed and internal state cleared as a side effect,
    /// matching FLTK's own `reap_editor()`).
    int reapEditor()
    {
        if (!isEditing()) return -2;

        typeof(tryWait(pid_)) result;
        try
            result = tryWait(pid_);
        catch (Exception)
            return -1; // FLTK: `waitpid()` failed
        if (!result.terminated)
            return 0;

        removeTmpfile(); // also clears fileMtime_/fileSize_
        running_ = false;
        pid_ = null;
        if (--editorsOpen_ <= 0)
            stopUpdateTimer();
        return 1;
    }

    private string createTmpdir()
    {
        string dirname = tmpdirName();
        if (!(exists(dirname) && isDir(dirname)))
        {
            try
                mkdir(dirname);
            catch (Exception e)
            {
                alert(format("can't create directory '%s': %s", dirname, e.msg));
                return null;
            }
        }
        return dirname;
    }

    private string tmpFilename()
    {
        string dir = createTmpdir();
        if (dir is null) return null;
        return buildPath(dir, format("%s.d", cast(void*) this));
    }

    private int startEditor(string editorCmd, string targetFilename)
    {
        commandLine_ = editorCmd;
        string[] args = editorCmd.split() ~ targetFilename;
        if (args.length == 0)
        {
            alert("ERROR: empty external editor command");
            return -1;
        }

        try
            pid_ = spawnProcess(args);
        catch (ProcessException e)
        {
            alert(format("Can't launch external editor '%s':\n%s", editorCmd, e.msg));
            return -1;
        }

        running_ = true;
        if (editorsOpen_++ == 0)
            startUpdateTimer();
        return 0;
    }

    // -- static bookkeeping, shared across every instance --

    /// Starts the app-wide polling timer (a no-op if no callback has
    /// been registered via `setUpdateTimerCallback()`) -- called
    /// automatically when the first editor of any instance opens.
    static void startUpdateTimer()
    {
        if (updateTimerCb_ is null) return;
        addTimeout(2.0, updateTimerCb_);
    }

    /// Stops the app-wide polling timer -- called automatically once
    /// the last open editor (across every instance) closes.
    static void stopUpdateTimer()
    {
        if (updateTimerCb_ is null) return;
        removeTimeout(updateTimerCb_);
    }

    /// Registers the app's own polling callback (expected to call
    /// `handleChanges()` on every open `ExternalCodeEditor` and, if it
    /// wants to keep polling, re-arm itself via `fl.core.
    /// repeatTimeout()` -- `Fl::add_timeout()`/this port's own `add
    /// Timeout()` are always one-shot, matching FLTK exactly).
    static void setUpdateTimerCallback(TimeoutHandler cb)
    {
        updateTimerCb_ = cb;
    }

    /// How many editors (across every instance) are currently open.
    static int editorsOpen() { return editorsOpen_; }

    /// This process's own temp directory for external-editor files.
    static string tmpdirName()
    {
        import std.process : thisProcessID;

        return format("/tmp/.fluid-%d", thisProcessID);
    }

    /// Removes the temp directory (called on app exit to clean up).
    static void tmpdirClear()
    {
        string dir = tmpdirName();
        if (exists(dir) && isDir(dir))
        {
            try
                rmdir(dir);
            catch (Exception e)
                alert(format("WARNING: can't remove directory '%s': %s", dir, e.msg));
        }
    }
}

unittest
{
    // Headless-testable slice: temp dir/file naming and creation,
    // save/reload-detection, and cleanup -- everything that doesn't
    // need an actual editor process or a live display.
    auto editor = new ExternalCodeEditor();
    assert(!editor.isEditing());
    assert(editor.filename() is null);

    string code = "void main() {}\n";
    // `/bin/true` always exits immediately -- exercises the real
    // spawnProcess()/write()-to-tempfile path without leaving an
    // editor window open for a headless test run.
    int rc = editor.openEditor("/bin/true", code);
    assert(rc == 0);
    assert(editor.filename() !is null);
    assert(exists(editor.filename()));
    assert((cast(string) read(editor.filename())) == code);

    // Wait for /bin/true to exit and get reaped via reapEditor() --
    // the same call the app's own periodic timer callback would make.
    import core.thread : Thread;
    import core.time : msecs;

    int tries;
    int reaped = 0;
    while (reaped == 0 && tries++ < 100)
    {
        Thread.sleep(20.msecs);
        reaped = editor.reapEditor();
    }
    assert(reaped == 1);
    assert(!editor.isEditing());
    assert(editor.filename() is null); // reapEditor() removes the tmpfile as a side effect

    destroy(editor);
    ExternalCodeEditor.tmpdirClear(); // leave no residue under /tmp from this test run
}
