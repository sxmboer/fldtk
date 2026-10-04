// D transliteration of FLTK's test/keyboard.cxx + test/keyboard.h
// (~/Repositories/fltk). Part of the samples/ contract -- see
// samples/README.md.
//
// keyboard_ui.fl (Fluid-generated -- see samples/test/generated/
// keyboard_ui.d once built) provides make_window(), the KeyBtn/ShiftBtn
// registration arrays (keyButtons_/shiftButtons_), and regKey()/
// regShift() -- see that .fl file's own top comment for the split.
// This file provides everything FLTK's own keyboard.cxx/.h
// hand-write: the MyWindow class (mouse-wheel -> rollerX/rollerY
// dispatch), the Escape-eating Fl::add_handler() callback, and main()'s
// polling loop (event_key()/event_state() -> button .value(), plus the
// keyname/text readouts).
module MyWindow;

import fl;
import keyboard_ui;
import fl.text_buffer : utf8Encode;
import std.format : format;

class MyWindow : Window
{
    Dial rollerX;
    Dial rollerY;

    this(int w, int h, string t = null)
    {
        super(w, h, t);
    }

    override int handle(Event event)
    {
        if (event == Event.mouseWheel)
        {
            rollerX.value(rollerX.value() + eventDx() * rollerX.step());
            rollerY.value(rollerY.value() + eventDy() * rollerY.step());
            return 1;
        }
        return 0;
    }
}

// Stops Esc from exiting the program; other shortcuts (zoom keys etc.)
// still pass through. Matches FLTK's free `handle(int e)`, installed
// via `Fl::add_handler(handle)`.
private int escapeGuard(Event e)
{
    if (e == Event.shortcut && eventKey() == escape)
        return 1;
    return 0;
}

private struct KeycodeEntry
{
    Keysym n;
    string text;
}

// Display names use fldtk's own bare D constant spelling, not FLTK's
// C `FL_*` macro name -- see source/test/handle_keys.d's identical table
// for the full reasoning (CLAUDE.md's memory notes on this standing
// rule).
private immutable KeycodeEntry[] keyTable = [
    KeycodeEntry(escape, "escape"),
    KeycodeEntry(backSpace, "backSpace"),
    KeycodeEntry(tab, "tab"),
    KeycodeEntry(isoKey, "isoKey"),
    KeycodeEntry(enter, "enter"),
    KeycodeEntry(print, "print"),
    KeycodeEntry(scrollLock, "scrollLock"),
    KeycodeEntry(pause, "pause"),
    KeycodeEntry(insert, "insert"),
    KeycodeEntry(home, "home"),
    KeycodeEntry(pageUp, "pageUp"),
    KeycodeEntry(deleteKey, "deleteKey"),
    KeycodeEntry(end, "end"),
    KeycodeEntry(pageDown, "pageDown"),
    KeycodeEntry(left, "left"),
    KeycodeEntry(up, "up"),
    KeycodeEntry(right, "right"),
    KeycodeEntry(down, "down"),
    KeycodeEntry(shiftL, "shiftL"),
    KeycodeEntry(shiftR, "shiftR"),
    KeycodeEntry(controlL, "controlL"),
    KeycodeEntry(controlR, "controlR"),
    KeycodeEntry(capsLock, "capsLock"),
    KeycodeEntry(altL, "altL"),
    KeycodeEntry(altR, "altR"),
    KeycodeEntry(metaL, "metaL"),
    KeycodeEntry(metaR, "metaR"),
    KeycodeEntry(menu, "menu"),
    KeycodeEntry(help, "help"),
    KeycodeEntry(numLock, "numLock"),
    KeycodeEntry(kpEnter, "kpEnter"),
    KeycodeEntry(altGr, "altGr"),
];

private string keyname(Keysym k)
{
    if (k == 0)
        return "0";
    if (k < 128)
        return format("'%c'", cast(char) k);
    if (k >= 0xa0 && k <= 0xff)
    {
        char[8] key;
        int kl = utf8Encode(cast(uint) k, key[]);
        return format("'%s'", key[0 .. kl]);
    }
    if (k > f && k <= fLast)
        return format("f+%d", k - f);
    if (k >= kp && k <= kpLast)
        return format("kp+'%c'", cast(char)(k - kp));
    if (k >= button && k <= button + 7)
        return format("button+%d", k - button);

    foreach (entry; keyTable)
        if (entry.n == k) return entry.text;
    return format("0x%04x", k);
}

void main(string[] args)
{
    addHandler((Event e) => escapeGuard(e));
    make_window();
    myWindow.show(args);

    while (firstWindow())
    {
        wait();

        foreach (kb; keyButtons_)
        {
            bool state = eventKey(kb.code);
            if (kb.btn.value() != state) kb.btn.value(state);
        }
        foreach (sb; shiftButtons_)
        {
            bool state = eventState(sb.bit) != 0;
            if (sb.btn.value() != state) sb.btn.value(state);
        }

        string kn = keyname(eventKey());
        if (keyOutput.value() != kn)
            keyOutput.value(kn);

        string txt = eventText();
        if (textOutput.value() != txt)
            textOutput.value(txt);
    }
}
