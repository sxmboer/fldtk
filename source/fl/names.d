/*
 * Ported from FL/names.h (FLTK 1.5.0): a small,
 * self-contained set of human-readable name lookup tables for three
 * enums, purely for debug/introspection use in *application* code
 * (nothing inside this port itself consumes these) -- e.g.
 * `writeln(eventNames[e])` instead of printing a bare integer while
 * tracing `handle()` calls.
 *
 * `eventNames` includes the pen events, which are members of `Event`
 * in this port (`Event.penTouch`, ...), under FLTK's names for them
 * (`"Fl::Pen::TOUCH"`, ...).
 *
 * `fontNames`/`callbackReasonNames` are plain `string[]` (index = the
 * enum's own underlying `int` value) rather than FLTK's
 * `std::map`/raw C array -- a D array already does exactly what
 * FLTK's C array does here, and `CallbackReason.user` (32) plus
 * `fontNames`/`callbackReasonNames`'s own gaps are handled the same way
 * FLTK's does: unnamed slots are `null` (FLTK: `NULL`).
 */
module fl.names;

import fl.enumerations : Event, Font, CallbackReason, helvetica, zapfDingbats;
import std.conv : to;

/// Human-readable names for every `Event` value -- ported from
/// `fl_eventnames` (`FL/names.h`).
immutable string[Event] eventNames;

shared static this()
{
    eventNames = [
        Event.noEvent: "FL_NO_EVENT",
        Event.push: "FL_PUSH",
        Event.release: "FL_RELEASE",
        Event.enter: "FL_ENTER",
        Event.leave: "FL_LEAVE",
        Event.drag: "FL_DRAG",
        Event.focus: "FL_FOCUS",
        Event.unfocus: "FL_UNFOCUS",
        Event.keyDown: "FL_KEYDOWN",
        Event.keyUp: "FL_KEYUP",
        Event.close: "FL_CLOSE",
        Event.move: "FL_MOVE",
        Event.shortcut: "FL_SHORTCUT",
        Event.deactivate: "FL_DEACTIVATE",
        Event.activate: "FL_ACTIVATE",
        Event.hide: "FL_HIDE",
        Event.show: "FL_SHOW",
        Event.paste: "FL_PASTE",
        Event.selectionClear: "FL_SELECTIONCLEAR",
        Event.mouseWheel: "FL_MOUSEWHEEL",
        Event.dndEnter: "FL_DND_ENTER",
        Event.dndDrag: "FL_DND_DRAG",
        Event.dndLeave: "FL_DND_LEAVE",
        Event.dndRelease: "FL_DND_RELEASE",
        Event.screenConfigurationChanged: "FL_SCREEN_CONFIGURATION_CHANGED",
        Event.fullscreen: "FL_FULLSCREEN",
        Event.zoomGesture: "FL_ZOOM_GESTURE",
        Event.zoomEvent: "FL_ZOOM_EVENT",
        Event.beforeTooltip: "FL_BEFORE_TOOLTIP",
        Event.beforeMenu: "FL_BEFORE_MENU",
        Event.appActivate: "FL_APP_ACTIVATE",
        Event.appDeactivate: "FL_APP_DEACTIVATE",
        Event.penDetected: "Fl::Pen::DETECTED",
        Event.penChanged: "Fl::Pen::CHANGED",
        Event.penInRange: "Fl::Pen::IN_RANGE",
        Event.penOutOfRange: "Fl::Pen::OUT_OF_RANGE",
        Event.penEnter: "Fl::Pen::ENTER",
        Event.penLeave: "Fl::Pen::LEAVE",
        Event.penTouch: "Fl::Pen::TOUCH",
        Event.penLift: "Fl::Pen::LIFT",
        Event.penHover: "Fl::Pen::HOVER",
        Event.penDraw: "Fl::Pen::DRAW",
        Event.penButtonPush: "Fl::Pen::BUTTON_PUSH",
        Event.penButtonRelease: "Fl::Pen::BUTTON_RELEASE",
        Event.rotateGesture: "ROTATE_GESTURE",
        Event.swipeGesture: "SWIPE_GESTURE",
        Event.touchDown: "TOUCH_DOWN",
        Event.touchMove: "TOUCH_MOVE",
        Event.touchUp: "TOUCH_UP",
        Event.touchCancel: "TOUCH_CANCEL",
    ];
}

/// Ported from `fl_eventname_str()` -- unlike `fontNameStr()`/
/// `callbackReasonStr()` below, this is a plain associative-array
/// lookup (matching FLTK's own `std::map`-based implementation),
/// so it has no equivalent off-by-one boundary bug: every valid key
/// (including future ones) is found or falls back correctly.
string eventNameStr(int event)
{
    auto p = cast(Event) event in eventNames;
    return p !is null ? *p : "FL_EVENT_" ~ event.to!string;
}

/// Human-readable names for every `Font` value, indexed by the font's
/// own `int` value. Ported from `fl_fontnames` (`FL/names.h`).
immutable string[] fontNames = [
    "FL_HELVETICA",
    "FL_HELVETICA_BOLD",
    "FL_HELVETICA_ITALIC",
    "FL_HELVETICA_BOLD_ITALIC",
    "FL_COURIER",
    "FL_COURIER_BOLD",
    "FL_COURIER_ITALIC",
    "FL_COURIER_BOLD_ITALIC",
    "FL_TIMES",
    "FL_TIMES_BOLD",
    "FL_TIMES_ITALIC",
    "FL_TIMES_BOLD_ITALIC",
    "FL_SYMBOL",
    "FL_SCREEN",
    "FL_SCREEN_BOLD",
    "FL_ZAPF_DINGBATS",
];

/**
 * Ported from `fl_fontname_str()`. **Faithfully replicates a real
 * FLTK off-by-one, not silently corrected** (logged in
 * `FLTK_ISSUES.md`): FLTK's own bounds check is
 * `if ((font < 0) || (font >= FL_ZAPF_DINGBATS)) return "FL_FONT_" +
 * to_string(font);` -- but `FL_ZAPF_DINGBATS` (15) is the *last valid*
 * index into a 16-entry array, so `font >= 15` incorrectly also
 * excludes that last valid entry, meaning `fl_fontname_str(FL_ZAPF_
 * DINGBATS)` never actually returns `"FL_ZAPF_DINGBATS"` -- it falls
 * through to the generic `"FL_FONT_15"` fallback instead, exactly like
 * every genuinely out-of-range value does. Looks like the boundary
 * constant should have been `FL_ZAPF_DINGBATS + 1` (or the comparison
 * `>`), not a deliberate exclusion.
 */
string fontNameStr(int font)
{
    if (font < 0 || font >= zapfDingbats) return "FL_FONT_" ~ font.to!string;
    return fontNames[font];
}

/// Human-readable names for `CallbackReason` values, indexed by the
/// reason's own `int` value -- `null` for unnamed slots (matching
/// FLTK's `NULL` entries), same as FLTK's own sparse array
/// between the last named reason (12) and `CallbackReason.user` (32).
/// Ported from `fl_callback_reason_names` (`FL/names.h`).
immutable string[] callbackReasonNames = [
    "FL_REASON_UNKNOWN",
    "FL_REASON_SELECTED",
    "FL_REASON_DESELECTED",
    "FL_REASON_RESELECTED",
    "FL_REASON_OPENED",
    "FL_REASON_CLOSED",
    "FL_REASON_DRAGGED",
    "FL_REASON_CANCELLED",
    "FL_REASON_CHANGED",
    "FL_REASON_GOT_FOCUS",
    "FL_REASON_LOST_FOCUS",
    "FL_REASON_RELEASED",
    "FL_REASON_ENTER_KEY",
    null, null, null, null, null, null, null, null, null, null,
    null, null, null, null, null, null, null, null, null,
    "FL_REASON_USER",
    "FL_REASON_USER+1",
    "FL_REASON_USER+2",
    "FL_REASON_USER+3",
];

/**
 * Ported from `fl_callback_reason_str()`. **Faithfully replicates the
 * same off-by-one pattern as `fontNameStr()` above, not silently
 * corrected** (logged in `FLTK_ISSUES.md`):
 * FLTK's bounds check is `if ((reason < 0) || (reason >=
 * FL_REASON_USER+3) || (fl_callback_reason_names[reason] == nullptr))`
 * -- but `FL_REASON_USER+3` (35) is the *last valid* index into a
 * 36-entry array, so `reason >= 35` incorrectly also excludes that
 * last valid entry: `fl_callback_reason_str(FL_REASON_USER+3)` never
 * returns `"FL_REASON_USER+3"`, it falls through to the generic
 * `"FL_REASON_35"` fallback instead. Same shape of bug as
 * `fontNameStr()`'s, in the same small header -- worth noting these
 * were found together, in case they share a root cause (a copy-pasted
 * boundary-check pattern).
 */
string callbackReasonStr(int reason)
{
    if (reason < 0 || reason >= CallbackReason.user + 3 || callbackReasonNames[reason] is null)
        return "FL_REASON_" ~ reason.to!string;
    return callbackReasonNames[reason];
}

unittest
{
    assert(eventNameStr(Event.push) == "FL_PUSH");
    assert(eventNameStr(9999) == "FL_EVENT_9999");

    assert(fontNameStr(helvetica) == "FL_HELVETICA");
    // The off-by-one: the *last* valid font never returns its real name.
    assert(fontNameStr(zapfDingbats) == "FL_FONT_15");
    assert(fontNameStr(-1) == "FL_FONT_-1");
    assert(fontNameStr(99) == "FL_FONT_99");

    assert(callbackReasonStr(CallbackReason.cancelled) == "FL_REASON_CANCELLED");
    assert(callbackReasonStr(20) == "FL_REASON_20"); // unnamed gap slot
    // The off-by-one: the *last* valid reason never returns its real name.
    assert(callbackReasonStr(CallbackReason.user + 3) == "FL_REASON_" ~ (CallbackReason.user + 3).to!string);
    assert(callbackReasonStr(CallbackReason.user + 2) == "FL_REASON_USER+2");
}
