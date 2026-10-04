// D transliteration of FLTK's test/unittest_terminal.cxx
// (~/Repositories/fltk). Part of the samples/ contract -- see
// samples/README.md. One tab of the "unittests" bundle; see
// samples/test/unittests.d for the registry.
// Check: ./samples/build.sh unittests
module unittest_terminal;

import fl;
import unittests;

import std.datetime.systime : Clock;
import std.datetime : SysTime;

//
//------- test the Fl_Terminal drawing capabilities ----------
//
class UtTerminalTest : FlGroup
{
    private Terminal tty1;
    private Terminal tty2;

    private void ansiTestPattern(Terminal tty)
    {
        tty.append("\033[30mBlack          Courier 14\033[0m Normal text\n"
            ~ "\033[31mRed            Courier 14\033[0m Normal text\n"
            ~ "\033[32mGreen          Courier 14\033[0m Normal text\n"
            ~ "\033[33mYellow         Courier 14\033[0m Normal text\n"
            ~ "\033[34mBlue           Courier 14\033[0m Normal text\n"
            ~ "\033[35mMagenta        Courier 14\033[0m Normal text\n"
            ~ "\033[36mCyan           Courier 14\033[0m Normal text\n"
            ~ "\033[37mWhite          Courier 14\033[0m Normal text\n"
            ~ "\033[1;30mBright Black   Courier 14\033[0m Normal text\n"
            ~ "\033[1;31mBright Red     Courier 14\033[0m Normal text\n"
            ~ "\033[1;32mBright Green   Courier 14\033[0m Normal text\n"
            ~ "\033[1;33mBright Yellow  Courier 14\033[0m Normal text\n"
            ~ "\033[1;34mBright Blue    Courier 14\033[0m Normal text\n"
            ~ "\033[1;35mBright Magenta Courier 14\033[0m Normal text\n"
            ~ "\033[1;36mBright Cyan    Courier 14\033[0m Normal text\n"
            ~ "\033[1;37mBright White   Courier 14\033[0m Normal text\n"
            ~ "\n"
            ~ "\033[31mRed\033[32mGreen\033[33mYellow\033[34mBlue\033[35mMagenta\033[36mCyan\033[37mWhite\033[0m - "
            ~ "\033[31mX\033[32mX\033[33mX\033[34mX\033[35mX\033[36mX\033[37mX\033[0m\n"
            ~ "\033[1;31mRed\033[1;32mGreen\033[1;33mYellow\033[34mBlue\033[35mMagenta\033[36mCyan\033[1;37mWhite\033[1;0m - "
            ~ "\033[1;31mX\033[1;32mX\033[1;33mX\033[1;34mX\033[1;35mX\033[1;36mX\033[1;37mX\033[0m\n");
    }

    private void grayTestPattern(Terminal tty)
    {
        tty.append("Grayscale Test Pattern\n"
            ~ "--------------------------\n"
            ~ "\033[38;2;255;255;255m 100% white     Courier 14\n" // ESC xterm codes for setting r;g;b colors
            ~ "\033[38;2;230;230;230m 90%  white     Courier 14\n"
            ~ "\033[38;2;205;205;205m 80%  white     Courier 14\n"
            ~ "\033[38;2;179;179;179m 70%  white     Courier 14\n"
            ~ "\033[38;2;154;154;154m 60%  white     Courier 14\n"
            ~ "\033[38;2;128;128;128m 50%  white     Courier 14\n"
            ~ "\033[38;2;102;102;102m 40%  white     Courier 14\n"
            ~ "\033[38;2;77;77;77m" ~ " 30%  white     Courier 14\n"
            ~ "\033[38;2;51;51;51m" ~ " 20%  white     Courier 14\n"
            ~ "\033[38;2;26;26;26m" ~ " 10%  white     Courier 14\n"
            ~ "\033[38;2;0;0;0m" ~ "  0%  white     Courier 14\n"
            ~ "\033[0m");
    }

    private static void dateTimerCb(Terminal tty)
    {
        SysTime lt = Clock.currTime();
        tty.printf("The time and date is now: %s", lt.toSimpleString());
        fl.repeatTimeout(3.0, { dateTimerCb(tty); });
    }

    static Widget create()
    {
        return new UtTerminalTest(UT_TESTAREA_X, UT_TESTAREA_Y, UT_TESTAREA_W, UT_TESTAREA_H);
    }

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        int ttyH = cast(int)(h / 2.25 + .5);
        int ttyY1 = y + ttyH * 0 + 20;
        int ttyY2 = y + ttyH * 1 + 40;

        // TTY1
        tty1 = new Terminal(x, ttyY1, w, ttyH, "Tty 1: Colors");
        ansiTestPattern(tty1);
        fl.addTimeout(0.5, { dateTimerCb(tty1); });

        // TTY2
        tty2 = new Terminal(x, ttyY2, w, ttyH, "Tty 2: Grayscale");
        grayTestPattern(tty2);
        fl.addTimeout(0.5, { dateTimerCb(tty2); });

        end();
    }
}

static this()
{
    new UnitTest(UT_TEST_SIMPLE_TERMINAL, "Terminal", () => UtTerminalTest.create());
}
