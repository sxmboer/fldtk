// D transliteration of FLTK's examples/howto-parse-args.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh howto-parse-args
import fl;
import std.format : format;

bool helpFlag = false;
string optionString;

/*
 * callback function passed to fl.args() to parse individual argument.
 * If there is a match, 'i' must be incremented by 2 or 1 as appropriate.
 * If there is no match, fl.args() will then call fl.arg() as fallback
 * to try to match the "standard" FLTK parameters.
 *
 * Returns 2 if args[i] matches with required parameter in args[i+1],
 * returns 1 if args[i] matches on its own,
 * returns 0 if args[i] does not match.
 */
int arg(string[] args, ref int i)
{
    if (args[i] == "-h" || args[i] == "--help")
    {
        helpFlag = true;
        i += 1;
        return 1;
    }

    if (args[i] == "-o" || args[i] == "--option")
    {
        if (i < args.length - 1 && args[i + 1] !is null)
        {
            optionString = args[i + 1];
            i += 2;
            return 2;
        }
    }
    return 0;
}

void main(string[] args)
{
    // Convert commandline arguments to UTF-8 on Windows.
    // This is a no-op on all other platforms (see documentation).
    fl.argsToUtf8(args);

    int i = 1;
    if (fl.args(args, i, (argv, ref j) => arg(argv, j)) < args.length)
        // note the concatenated strings to give a single format string!
        fl.fatal(format("error: unknown option: %s\n"
            ~ "usage: %s [options]\n"
            ~ " -h | --help     : print extended help message\n"
            ~ " -o | --option # : example option with parameter\n"
            ~ " plus standard fltk options\n",
            args[i], args[0]));
    if (helpFlag)
        fl.fatal(format("usage: %s [options]\n"
            ~ " -h | --help     : print extended help message\n"
            ~ " -o | --option # : example option with parameter\n"
            ~ " plus standard fltk options:\n"
            ~ "%s\n",
            args[0], fl.argsHelp));

    auto mainWin = new Window(300, 200);
    auto textBox = new Box(0, 0, 300, 200);
    if (optionString !is null)
        textBox.label(optionString);
    else
        textBox.label("re-run with [-o|--option] text");

    mainWin.resizable(mainWin);
    mainWin.show(args);
    fl.run();
}
