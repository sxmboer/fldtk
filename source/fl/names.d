/*
 * Names of events, fonts and callback reasons as they are written in D
 * (`"Event.penTouch"`, `"helveticaBold"`, `"CallbackReason.changed"`),
 * for debugging output: `writeln(eventNames[e])` instead of a bare
 * number while tracing `handle()` calls. Port of `FL/names.h`.
 *
 * The event and callback-reason names come from the enums themselves,
 * so a new member has its name at once. A value without a name gives
 * the D cast that would make it (`"cast(Event) 9999"`).
 */
module fl.names;

import fl.enumerations : Event, Font, CallbackReason, helvetica, zapfDingbats;
import std.conv : to;

/// The name of every `Event` value: `"Event.push"`, `"Event.penTouch"`.
immutable string[Event] eventNames;

shared static this()
{
    string[Event] names;
    static foreach (m; __traits(allMembers, Event))
        if (__traits(getMember, Event, m) !in names)
            names[__traits(getMember, Event, m)] = "Event." ~ m;
    eventNames = cast(immutable) names;
}

/// The name of an `Event` value (`"Event.push"`), or `"cast(Event) <n>"`
/// for a value without one.
string eventNameStr(int event)
{
    auto p = cast(Event) event in eventNames;
    return p !is null ? *p : "cast(Event) " ~ event.to!string;
}

/// The names of the standard fonts, indexed by the font's value:
/// `fontNames[helveticaBold]` is `"helveticaBold"`.
immutable string[] fontNames = [
    "helvetica",
    "helveticaBold",
    "helveticaItalic",
    "helveticaBoldItalic",
    "courier",
    "courierBold",
    "courierItalic",
    "courierBoldItalic",
    "times",
    "timesBold",
    "timesItalic",
    "timesBoldItalic",
    "symbol",
    "screen",
    "screenBold",
    "zapfDingbats",
];

/// The name of a `Font` value (`"helvetica"`), or `"cast(Font) <n>"` for
/// a font without one (fonts added with `setFont()`).
string fontNameStr(int font)
{
    if (font < 0 || font >= cast(int) fontNames.length) return "cast(Font) " ~ font.to!string;
    return fontNames[font];
}

/// The name of a `CallbackReason` value (`"CallbackReason.changed"`;
/// `"CallbackReason.user + 2"` above `user`), or `"cast(CallbackReason)
/// <n>"` for a value without one.
string callbackReasonStr(int reason)
{
    static foreach (m; __traits(allMembers, CallbackReason))
        if (reason == __traits(getMember, CallbackReason, m)) return "CallbackReason." ~ m;
    if (reason > CallbackReason.user)
        return "CallbackReason.user + " ~ (reason - CallbackReason.user).to!string;
    return "cast(CallbackReason) " ~ reason.to!string;
}

unittest
{
    assert(eventNameStr(Event.push) == "Event.push");
    assert(eventNameStr(Event.penTouch) == "Event.penTouch");
    assert(eventNames[Event.noEvent] == "Event.noEvent");
    assert(eventNameStr(9999) == "cast(Event) 9999");

    assert(fontNameStr(helvetica) == "helvetica");
    assert(fontNameStr(zapfDingbats) == "zapfDingbats");
    assert(fontNameStr(zapfDingbats + 1) == "cast(Font) 16");
    assert(fontNameStr(-1) == "cast(Font) -1");

    assert(callbackReasonStr(CallbackReason.cancelled) == "CallbackReason.cancelled");
    assert(callbackReasonStr(CallbackReason.user) == "CallbackReason.user");
    assert(callbackReasonStr(CallbackReason.user + 3) == "CallbackReason.user + 3");
    assert(callbackReasonStr(20) == "cast(CallbackReason) 20");
}
