/*
 * Output buffering for a program that File > Run in Fluid starts.
 *
 * Fluid reads such a program's output through a pipe, and the C library
 * buffers output to a pipe in blocks, so `writeln()` output would show
 * in Fluid's Run window only when a block is full or the program ends.
 * When the environment variable `FLDTK_FLUSH_OUTPUT` is set, which Fluid
 * does for the program it runs (`fluid.run_program`), this module's
 * constructor makes `stdout` line buffered before `main()` runs; on
 * Windows, whose C library has no line buffering, unbuffered. Without
 * the variable nothing changes.
 *
 * The module imports nothing from fldtk, so its constructor can't take
 * part in a constructor cycle; `fl.core` imports it so that it is
 * linked into every program, also from the static library on Windows.
 */
module fl.output_buffering;

shared static this()
{
    import core.stdc.stdlib : getenv;
    import core.stdc.stdio : setvbuf, stdout, _IOLBF, _IONBF, BUFSIZ;

    if (getenv("FLDTK_FLUSH_OUTPUT") is null) return;
    version (Windows)
        setvbuf(stdout, null, _IONBF, 0);
    else
        setvbuf(stdout, null, _IOLBF, BUFSIZ);
}
