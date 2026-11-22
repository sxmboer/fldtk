# The X11 pen driver: how tablets reach programs on X11

Design notes for `fl.x11_pen_driver`, the pen driver of fldtk's X11
backend (see `docs/PORTING.md`, `FL/core/pen_events.H`). FLTK has no X11
pen driver, so these notes come from the XInput2 protocol, from reading
how two toolkits that support tablets on X11 do it, and from recording
what a real tablet sends (section 5):

- Qt 5.15, `src/plugins/platforms/xcb/qxcbconnection_xi2.cpp` (the
  tablet support Krita relies on),
- GTK 3.24, `gdk/x11/gdkdevicemanager-xi2.c`.

Nothing is taken from either; the driver is written from these notes,
and the pseudo-code in section 4 is what it does.

## 1. What the X server offers

### Devices

XInput2 lists every input device with `XIQueryDevice(display,
XIAllDevices, &n)`. A device is either a *master* (the one pointer and
one keyboard everybody sees; the cursor) or a *slave* (a real piece of
hardware attached to a master: a mouse, a touchpad, a tablet's pen).
Every slave pointer moves the master pointer, so the core events
(`ButtonPress`, `MotionNotify`) a program normally gets come from the
master, whichever slave caused them.

A tablet shows up as one or more slave pointers. Their names depend on
the X driver:

| Driver | Typical slave names |
|---|---|
| `xf86-input-wacom` | `Wacom Intuos Pro M Pen stylus`, `... Pen eraser`, `... Pen cursor`, `... Pad pad` |
| `xf86-input-libinput` | `<tablet name> Pen (0)`, `<tablet name> Eraser (0)` |
| Xwayland (an X11 program on a Wayland desktop) | `xwayland-tablet stylus:NN`, `xwayland-tablet eraser:NN`, `xwayland-tablet cursor:NN` |

Each device has *classes*. For a pen, the important one is the
**valuator class**: one per axis, each with a number (its index in
events), a label (an X atom) and a range:

| Label atom | Meaning |
|---|---|
| `Abs X`, `Abs Y` | position on the tablet |
| `Abs Pressure` | tip or eraser pressure |
| `Abs Tilt X`, `Abs Tilt Y` | tilt, usually -64..63, in degrees |
| `Abs Wheel` | an airbrush's finger wheel or an Art Pen's rotation |

The button class gives the buttons: button 1 is the tip, 2 the lower
barrel button, 3 the upper one (the drivers' default mapping).

### Telling a pen from other devices

Neither toolkit has anything better than looking at the axes and the
name:

- **Qt:** a slave with `Abs X`, `Abs Y` and `Abs Pressure` might be a
  tablet; the name then decides. It contains "eraser" → eraser;
  "cursor" → puck; "pen" or "stylus" → pen; "wacom" without "touch" →
  pen. A few brand names (aiptek, waltop, uc-logic, ugee) count as pens
  too.
- **GTK:** name contains "eraser" → eraser, "cursor" → puck, " pad" →
  the tablet's button pad, "wacom", "pen" or "stylus" → pen. With
  `xf86-input-wacom` it also reads the device property `Wacom Tool
  Type` (an atom: `STYLUS`, `ERASER`, `CURSOR`, `PAD`, `TOUCH`).

For fldtk: **a slave pointer with an `Abs Pressure` valuator whose name
does not contain "pad", "touch" or "finger"** is a pen, and an eraser if
the name contains "eraser". That covers all three drivers above
without a list of brands.

### Events

A program asks for XInput2 events per window and per device with
`XISelectEvents()`: `XI_ButtonPress`, `XI_ButtonRelease`, `XI_Motion`,
and so on. They arrive as `GenericEvent`s, read through
`XGetEventData()` (fldtk's `handleXInput2()` already does this for
touch). An `XIDeviceEvent` carries:

- `deviceid`: the device it was selected for; `sourceid`: the slave
  that caused it,
- `event_x`, `event_y` (window coordinates, with a fraction),
  `root_x`, `root_y`,
- `detail`: the button number,
- `valuators`: a bit mask of which axes changed, and their values,
  in valuator-number order, for the set bits only.

Only the axes that changed are in an event, so the driver keeps each
axis's last value.

### Proximity

XInput2 has no event for "the pen came near / went away".

- With `xf86-input-wacom`, both toolkits watch the device property
  `Wacom Serial IDs` (`XI_PropertyEvent`): its fourth item (the tool's
  serial) becomes nonzero when a tool comes near and 0 when it leaves.
  This also tells pens apart by serial number.
- With `xf86-input-libinput` and Xwayland there is no such property.
  The older XInput 1 protocol has `ProximityIn` / `ProximityOut` events,
  but the recorded tablet sent none (section 5), so they aren't used.
  Instead, the first event from a pen device counts as "in range", and
  `XI_Leave` (the pen left the window) as "out of range".

## 2. How the two toolkits receive the events

**Qt (its fallback mode):** selects button and motion events on each
tablet slave, per window. The core events from the master keep coming
as well; Qt's tablet code handles the slave event and the core mouse
event is a separate stream.

**Qt (default) and GTK:** select button, motion, enter and leave on
`XIAllMasterDevices` for each window. The server then sends XInput2
events *instead of* the core events for that window, every one with a
`sourceid`; the program looks the source up and treats the event as a
pen event or a mouse event. This means the whole mouse path runs on
XInput2.

## 3. The fldtk side: what already exists

- `fl.pen` does the dispatch for every driver: `dispatchPenFrame(tool,
  frame, platform)` takes a `PenTool` (whose `ev` holds position,
  pressure, tilt, state) and a `PenFrame` (`proximityIn`,
  `proximityOut`, `down`, `up`, `motion`, buttons pressed and released)
  and does the rest: finding the subscriber under the pen, `penEnter`,
  `penTouch`, `penDraw`, ..., and turning unclaimed pen input into mouse
  events when `PenPlatform.sendsMouseEvents` is false.
- `fl.xinput2` binds the part of libXi used for touch;
  `fl.platform_x11` checks the XInput version (`initXInput2()`),
  selects touch events per toplevel window (`selectTouch()`) and reads
  generic events (`handleXInput2()`).
- `fl.wayland_pen_driver` shows the pattern: callbacks update the
  tool's `ev` and its `PenFrame`; one call per frame dispatches.

So the X11 driver only has to find the pens, receive their events, fill
in `PenTool.ev` and a `PenFrame` per event, and call
`dispatchPenFrame()`.

## 4. The driver, in pseudo-code

### Choice: which events to select

Two ways, from section 2:

- **A. Select on the pen slaves only** (Qt's fallback). The mouse path
  stays as it is. The server also sends the core events the pen
  causes, so the driver sets `sendsMouseEvents = true` (as on Windows):
  an unclaimed pen works as a mouse through those core events. While a
  subscriber holds the pen, the core pointer events the pen caused must
  be dropped. Each core event caused by a pen has the same timestamp as
  the pen's XInput2 event, so the driver remembers the time of the last
  pen event it dispatched to a subscriber and the core path skips
  `ButtonPress` / `ButtonRelease` / `MotionNotify` with that time.
- **B. Select on `XIAllMasterDevices`** (GTK, Qt's default). No
  duplicate events, but every mouse event then arrives through
  XInput2, and the core mouse path in `fl.platform_x11` (buttons,
  wheel, enter and leave, grabs) has to move there.

A is much smaller and keeps the mouse path untouched; fldtk uses it.
The recording in section 5 shows the timestamps match, and that the
pen's own event comes first.

`XISelectEvents()` replaces a window's previous selection for the same
device, so the pen slaves are selected in a call of their own, not
together with the touch selection on `XIAllMasterDevices`.

### Finding the pens

```
struct X11Pen : PenTool              // fl.pen's tool, plus:
    int deviceId
    int pressureAxis = -1, tiltXAxis = -1, tiltYAxis = -1
    double[axis] min, max, last      // last value of each axis
    bool inRange

X11Pen[] pens

findPens():                          // at startup, and on XI_HierarchyChanged
    pens = []
    for each device in XIQueryDevice(XIAllDevices):
        if device.use != XISlavePointer: continue
        name = lowercase(device.name)
        if name contains "pad" or "touch" or "finger": continue
        pen = new X11Pen(deviceId = device.id)
        for each valuator class v of device:
            switch atomName(v.label):
                "Abs Pressure": pen.pressureAxis = v.number
                "Abs Tilt X":   pen.tiltXAxis = v.number
                "Abs Tilt Y":   pen.tiltYAxis = v.number
            pen.min[v.number] = v.min; pen.max[v.number] = v.max
        if pen.pressureAxis < 0: continue          // not a pen
        pen.eraser = name contains "eraser"
        pen.penId = device.id
        pen.capabilities = pressure | tiltX/tiltY when those axes exist
                           | eraser when pen.eraser
        pens ~= pen
    for each fldtk toplevel window: selectPens(window)

selectPens(window):                  // when a window is mapped, and after findPens()
    masks = for each pen: { deviceid: pen.deviceId,
                            bits: XI_ButtonPress, XI_ButtonRelease, XI_Motion,
                                  XI_Enter, XI_Leave }
    XISelectEvents(display, window, masks)
```

`findPens()` runs when the first widget subscribes (`Pen.subscribe()`
calls the platform's first-subscriber hook), so programs without pen
widgets ask for nothing. `XI_HierarchyChanged`, selected on the root
window, says a device was added or removed; `xf86-input-libinput`
creates a tool's device the first time it comes near.

### Handling an event

```
handlePenEvent(XIDeviceEvent e):     // from handleXInput2(), before touch
    pen = pens.find(e.sourceid) or return false
    window = fldtk window of e.event or return true

    // the axes that changed
    i = 0
    for axis in 0 .. e.valuators.mask_len * 8:
        if bit axis set in e.valuators.mask:
            pen.last[axis] = e.valuators.values[i++]

    ev = pen.ev
    ev.x, ev.y   = e.event_x, e.event_y  / the screen scale
    ev.rx, ev.ry = e.root_x, e.root_y    / the screen scale
    ev.pressure  = normalized(pen, pen.pressureAxis)              // 0..1
    ev.tiltX     = pen.last[pen.tiltXAxis] / 90  when the axis exists   // degrees -> -1..1
    ev.tiltY     = pen.last[pen.tiltYAxis] / 90  when the axis exists
    pen.focusWin = window

    frame = PenFrame()
    hover = pen.eraser ? eraserHovers : tipHovers
    down  = pen.eraser ? eraserDown   : tipDown

    if not pen.inRange and e.evtype != XI_Leave:
        pen.inRange = true
        frame.proximityIn = true
        ev.state = hover | (ev.state & buttons)

    switch e.evtype:
        XI_ButtonPress:
            if e.detail == 1: ev.state = down | (ev.state & buttons); frame.down = true
            else: bit = (e.detail == 2 ? button0 : e.detail == 3 ? button1 : none)
                  ev.state |= bit; frame.buttonsPressed |= bit
        XI_ButtonRelease:
            if e.detail == 1: ev.state = hover | (ev.state & buttons); frame.up = true
            else: (as above, clearing the bit; frame.buttonsReleased |= bit)
        XI_Motion:
            frame.motion = true
        XI_Leave:
            pen.inRange = false
            frame.proximityOut = true

    platform = PenPlatform(sendsMouseEvents = true)
    if dispatchPenFrame(pen, frame, platform):
        lastClaimedTime = e.time     // the core path drops core events with this time
    if frame.proximityOut: pen.focusWin = null
    return true

normalized(pen, axis):
    if axis < 0: return 1            // fl.pen: 1 when not reported
    return (pen.last[axis] - pen.min[axis]) / (pen.max[axis] - pen.min[axis])
```

In the core event path of `fl.platform_x11`:

```
case ButtonPress, ButtonRelease, MotionNotify:
    if event.time == x11PenDriver.lastClaimedTime: break   // the pen's own copy
    ... as now
```

### Traits

`traits()` reports `driverAvailable` once XInput 2.0 or later is
there, plus `pressure`, `tiltX`, `tiltY`, `eraser`, `penId`, and
`detected` once `pens` is not empty. Twist, barrel pressure and the
distance from the surface are not reported (they need `Abs Wheel` and
a distance axis with tool-specific meanings; left out).

## 5. What a real tablet sends

Recorded with a Veikk VK1060 Pro on an X11 session with the Wacom X
driver, using `xinput list`, `xinput list --long <id>`,
`xinput list-props <id>`, `xinput test-xi2 --root` and `xinput test <id>`:

- **Devices:** `VEIKK.INC VK1060PRO stylus`, `... eraser` (each a slave
  pointer), `... Mouse` (the tablet's mouse mode, no pressure axis) and
  `... Keyboard` (the express keys, as keystrokes).
- **Axes**, the same for stylus and eraser: `Abs X` 0..19200, `Abs Y`
  0..32000, `Abs Pressure` 0..65536, `Abs Tilt X` and `Abs Tilt Y`
  -64..63. The stylus also has `Abs Wheel` -900..899 (unused by this
  pen), both have two scroll axes.
- **Properties:** `Wacom Tool Type` is `STYLUS`; `Wacom Serial IDs`
  exists and changes (an `XI_PropertyEvent`) each time the pen comes
  near or goes away. The first motion event can arrive just before the
  property change, so a pen event also brings a pen into range.
- **Timestamps:** every pen event arrives first from the stylus device,
  then from the master pointer with the same timestamp; the core mouse
  event is the master's.
- **Barrel buttons:** this tablet sends them as key presses from its
  `Keyboard` device (keycodes 56 and 26, the letters b and e), not as
  buttons 2 and 3, so no pen driver can report them; pressing one also
  makes the pen briefly go out of range and back.
- **XInput 1** (`xinput test`): motion only; no proximity events.
