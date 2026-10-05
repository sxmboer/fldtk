// D transliteration of FLTK's examples/howto-add_fd-and-popen.cxx.
// Build: rdmd buildsamples.d examples howto_add_fd_and_popen
//
// FLTK reaches for raw C `popen()`/`pclose()`/`fileno()`/`fgets()`
// since C++ has nothing better. `std.process.pipeShell()` is the clean
// D-native equivalent of `popen()` -- it returns a `std.stdio.File` for
// the child's stdout, and `File.fileno` exposes the same raw OS file
// descriptor `fl.addFd()` needs, so no `core.stdc`/`core.sys.posix`
// import is needed at all here. `File.readln()` + `.eof` replaces the
// per-call `fgets()` pattern (one line read per `addFd()` invocation,
// matching FLTK's own per-call shape), and `std.process.wait()`
// replaces `pclose()`.

import fl;
import std.process : pipeShell, ProcessPipes, Redirect, wait, ProcessException;
import std.stdio : stderr;

// 'slow command' -- Windows' ping has no -i (interval)/-c (count)
// options (-i means TTL there), so needs its own syntax; see this
// file's own header comment.
version (Windows)
    enum string pingCmd = "ping -n 10 localhost";
else
    enum string pingCmd = "ping -i 2 -c 10 localhost";

// GLOBALS
ProcessPipes gPipes;

// Handler for addFd() -- called whenever the ping command outputs a new
// line of data.
void handleFd(int fd, MultiBrowser brow)
{
    string line = gPipes.stdout.readln(); // read the line of data
    if (line.length == 0 && gPipes.stdout.eof)
    {
        fl.removeFd(fd);   // command ended? disconnect callback
        wait(gPipes.pid);  // reap the child process
        brow.add("");
        brow.add("<<DONE>>");       // append msg indicating command finished
        return;
    }
    brow.add(line); // line of data read? append to widget
}

void main(string[] args)
{
    auto win = new Window(600, 600);
    auto brow = new MultiBrowser(10, 10, 580, 580);
    try
        gPipes = pipeShell(pingCmd, Redirect.stdout); // start the external unix command
    catch (ProcessException e)
    {
        stderr.writefln("pipeShell failed: %s", e.msg);
        return;
    }
    fl.addFd(gPipes.stdout.fileno, (fd) { handleFd(fd, brow); }); // callback for the piped descriptor
    win.resizable(brow);
    win.show(args);
    fl.run();
}
