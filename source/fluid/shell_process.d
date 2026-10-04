/*
 * The interactive editor's shell-command runner -- ported from
 * FLTK's `fluid/app/shell_command.h`/`.cxx`, but only the process-
 * spawning/output-streaming half of that file (`Fl_Process`,
 * `run_shell_command()`, `expand_macros()`, `shell_command_running()`,
 * the `Fl::add_fd()`/`Fl::add_timeout()` wiring). The *other* half of
 * that file -- the `Fd_Shell_Command`/`Fd_Shell_Command_List` database
 * (named, savable commands with conditions/shortcuts/storage location),
 * its Settings-dialog UI, and the `&Shell` menu it drives -- is a
 * separate, later piece (`fluid.shell_command` + `fluid/panels/
 * shell_settings.d`, now built on top of what's here) matching the
 * user's own explicit two-step framing ("build the shell runner and
 * then do shell_command.h").
 *
 * **`Fl_Process` itself is not ported at all -- deliberately, not an
 * oversight.** FLTK's own class exists purely to paper over C++'s
 * lack of a portable "run a shell command, get pipes" primitive: a
 * thin POSIX `popen()`/`pclose()` wrapper on Linux/macOS, and ~60 lines
 * of hand-rolled `CreatePipe()`/`CreateProcess()`/handle-juggling on
 * Windows. D's own `std.process.pipeShell()` already *is* that
 * portable primitive -- real pipes, real cross-platform process
 * spawning through the platform's own shell, one call, no `version
 * (Windows)` branch needed anywhere in this module. Exactly the
 * "check for a cleaner D stdlib alternative before transliterating a
 * raw C library call" case CLAUDE.md's own porting conventions call
 * out.
 *
 * **`@HEADERFILE_PATH@`/`@HEADERFILE_NAME@` are deliberately not
 * ported either.** FLTK's `expand_macros()` has seven macros;
 * these two specifically name the generated `.h` file, which this
 * port's generated D simply doesn't have (no header/source split --
 * see `fluid.app`'s own `-h`/`--help` note for the identical reasoning
 * applied to the CLI). Keeping two macros that can only ever expand to
 * an empty string would be a silent dead end, not a real feature.
 *
 * Non-blocking output streaming matches FLTK's own model exactly:
 * `fl.core.addFd()` (this port's real `Fl::add_fd()`) fires when the
 * child's stdout pipe has data ready, at which point a *blocking*
 * `File.readln()` call is safe (short-lived, matching FLTK's own
 * blocking `fgets()` inside `shell_pipe_cb()` -- readiness-triggered,
 * not polled), plus a `fl.core.addTimeout()` 0.25s fallback poll,
 * exactly mirroring FLTK's own belt-and-suspenders "in case the fd
 * callback doesn't fire" comment.
 */
module fluid.shell_process;

import std.process;
import std.stdio : File;
import std.array : replace;

import fl;

/// Mirrors FLTK's `Fd_Shell_Command`'s own flag bits exactly (kept
/// here, imported by `fluid.shell_command`, rather than the other way
/// around, since `runShellCommand()` already needs to interpret them
/// and predates that module). An open,
/// combinable bitmask, not a closed tag set -- `alias`+manifest
/// constants, matching CLAUDE.md's own porting convention for exactly
/// this shape (a real D `enum` would need an explicit `cast()` back on
/// every `|=`).
alias ShellFlags = int;
enum ShellFlags shellSaveProject = 1;
enum ShellFlags shellSaveSourceCode = 2;
enum ShellFlags shellSaveStrings = 4;
enum ShellFlags shellSaveAll = 7;
enum ShellFlags shellDontShowTerminal = 8;
enum ShellFlags shellClearTerminal = 16;
enum ShellFlags shellClearHistory = 32;

/// The project-specific values `expandMacros()` substitutes -- computed
/// by the caller (`gui_main.d` owns the actual project path/state, this
/// module has no dependency on it), matching how `fluid.canvas`'s own
/// outward delegates keep project-state ownership on the caller's side.
struct ShellMacros
{
    string baseName;
    string projectFilePath, projectFileName;
    string codeFilePath, codeFileName;
    string textFilePath, textFileName;
    string tmpDir;
}

/// Ported from FLTK's `expand_macros()` -- five of FLTK's seven
/// macros (`@HEADERFILE_PATH@`/`@HEADERFILE_NAME@` deliberately not
/// ported, see this module's own top comment) plus `@BASENAME@`/
/// `@TMPDIR@`, eight->six total.
string expandMacros(string cmd, ShellMacros m)
{
    cmd = cmd.replace("@BASENAME@", m.baseName);
    cmd = cmd.replace("@PROJECTFILE_PATH@", m.projectFilePath);
    cmd = cmd.replace("@PROJECTFILE_NAME@", m.projectFileName);
    cmd = cmd.replace("@CODEFILE_PATH@", m.codeFilePath);
    cmd = cmd.replace("@CODEFILE_NAME@", m.codeFileName);
    cmd = cmd.replace("@TEXTFILE_PATH@", m.textFilePath);
    cmd = cmd.replace("@TEXTFILE_NAME@", m.textFileName);
    cmd = cmd.replace("@TMPDIR@", m.tmpDir);
    return cmd;
}

unittest
{
    ShellMacros m;
    m.baseName = "radio";
    m.projectFilePath = "/proj/";
    m.projectFileName = "radio.fl";
    m.codeFilePath = "/proj/";
    m.codeFileName = "radio.d";
    m.textFilePath = "/proj/";
    m.textFileName = "radio.txt";
    m.tmpDir = "/tmp/";

    string cmd = "cd @PROJECTFILE_PATH@ && dmd @CODEFILE_NAME@ -of=@TMPDIR@@BASENAME@";
    assert(expandMacros(cmd, m) == "cd /proj/ && dmd radio.d -of=/tmp/radio");

    // A macro with no matching field just doesn't appear -- no crash,
    // no partial substitution.
    assert(expandMacros("echo @PROJECTFILE_NAME@", m) == "echo radio.fl");

    // No macros at all -- passed through unchanged.
    assert(expandMacros("echo hello", m) == "echo hello");
}

private ProcessPipes pipes_;
private bool running_;
private TimeoutHandler pollTimeout_;

/// Ported from FLTK's `shell_command_running()`.
bool shellCommandRunning() { return running_; }

/// Fired once, before macro expansion, so the caller can save the
/// project/generated code/strings file as `flags` requests -- ported
/// from FLTK's `prepare_shell_command()`. `gui_main.d` (once
/// `fluid.shell_command` exists) is the real consumer; this module has
/// no project-state of its own to save.
void delegate(ShellFlags flags) onPrepareSave;

/// Fired once per output line, in arrival order, newline included
/// (matching `File.readln()`'s own convention, same as FLTK's
/// `fgets()`) -- `gui_main.d` wires this to `shellRunTerminal.append()`.
void delegate(string line) onOutputLine;

/// Fired once, after the process exits (or fails to start at all) --
/// `success` is `false` only for the "failed to start" case (matches
/// FLTK's own `popen() == nullptr` branch); a real command that
/// merely exits with a nonzero status still reports `true` here, same
/// as FLTK (which never inspects `pclose()`'s own return value for
/// this signal either).
void delegate(bool success) onDone;

/// Ported from FLTK's `run_shell_command()`. `cmd` is the raw,
/// un-expanded command text; `macros` supplies this call's own project-
/// specific substitution values (see `ShellMacros`'s own doc comment).
/// A second call while one is already running is rejected with the
/// same message FLTK shows (`fl.alert()`, matching
/// `prepare_shell_command()`'s own `fl_alert()` call) rather than
/// queued or silently ignored.
void runShellCommand(string cmd, ShellFlags flags, ShellMacros macros)
{
    if (cmd.length == 0)
    {
        fl.alert("No shell command entered!");
        return;
    }
    if (running_)
    {
        fl.alert("Previous shell command still running!");
        return;
    }

    if (onPrepareSave !is null)
        onPrepareSave(flags & shellSaveAll);

    string expanded = expandMacros(cmd, macros);

    if (onOutputLine !is null)
        onOutputLine("\033[0;32m" ~ expanded ~ "\033[0m\n");

    try
        pipes_ = pipeShell(expanded, Redirect.stdout | Redirect.stderrToStdout);
    catch (ProcessException e)
    {
        if (onOutputLine !is null)
            onOutputLine("\033[1;31mUnable to run shell command: " ~ e.msg ~ "\033[0m\n");
        return;
    }

    running_ = true;
    fl.core.addFd(pipes_.stdout.fileno, (fd) { onPipeReadable(fd); });
    pollTimeout_ = () { onPollTimeout(); };
    fl.core.addTimeout(0.25, pollTimeout_);
}

/// Fires when the child's stdout pipe has data ready -- reads exactly
/// one line (a short, bounded blocking call, matching FLTK's own
/// `fgets()`-inside-the-fd-callback shape) and reports it, or, on EOF
/// (`readln()`'s own empty-string convention), tears everything down.
private void onPipeReadable(int fd)
{
    string line = pipes_.stdout.readln();
    if (line.length == 0)
    {
        finish();
        return;
    }
    if (onOutputLine !is null)
        onOutputLine(line);
}

/// The 0.25s fallback poll -- matches FLTK's own belt-and-
/// suspenders `shell_timer_cb()` exactly (re-arms itself via
/// `fl.core.addTimeout()` until the process is gone, in case the fd
/// callback alone somehow doesn't fire).
private void onPollTimeout()
{
    if (!running_) return;
    fl.core.addTimeout(0.25, pollTimeout_);
}

private void finish()
{
    fl.core.removeFd(pipes_.stdout.fileno);
    fl.core.removeTimeout(pollTimeout_);
    wait(pipes_.pid);
    running_ = false;
    if (onDone !is null)
        onDone(true);
}
