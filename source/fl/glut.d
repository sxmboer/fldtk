/*
 * Port of `FL/glut.H` + `src/glut_compatibility.cxx` (FLTK 1.5.0): GLUT emulation built on top of `fl.gl_window`.
 *
 * **Scope**: determined by grepping every `glut*`/`glu*` call site
 * across the 5 GLUT-dependent samples (`source/test/
 * glut_test.d`/`glpuzzle.d`/`fractals.d`/`fracviewer.d`, `source/
 * examples/OpenGL3_glut_test.d`), not assumed from the "thousands of
 * lines of freeglut teapot/font data" FLTK's own `src/*glut*`/
 * `src/freeglut_*` might suggest. **Zero** call sites for any `glutWire*`/
 * `glutSolid*`/`glutStroke*`/`glutBitmap*` primitive exist anywhere in
 * this port's sample tree, so `freeglut_geometry.cxx`/`freeglut_teapot*`/
 * `freeglut_stroke_roman.cxx`/`freeglut_stroke_mono_roman.cxx`/
 * `glut_font.cxx` (~7300 of the ~7800 FLTK lines under `src/
 * *glut*`/`src/freeglut_*`) are **deliberately not ported** -- a
 * confirmed, considered omission (see `PORTING.md`'s `FL/glut.H` row),
 * not an oversight or a gap left for later -- that stands unless a
 * future sample actually calls one of these primitives. What *is* needed,
 * and *is* ported here, in full (not just the subset any one sample
 * happens to call -- see CONVENTIONS.md on why partial,
 * demo-scoped "coverage" is exactly the failure mode to avoid): the
 * whole real `glut_compatibility.cxx` window/callback/menu emulation
 * layer, plus every non-commented-out declaration in `FL/glut.H`. The
 * only declarations skipped are ones FLTK's own `FL/glut.H` already
 * has commented out (spaceball/dial/tablet/button-box/window-status/
 * colormap functions -- never real, callable API even in real GLUT-on-
 * FLTK, not a scope cut made here). GLU (`gluLookAt()`/`gluPerspective()`/
 * etc, needed by `fracviewer.d`'s camera and `glpuzzle.d`'s puzzle-piece
 * geometry) is a separate module, `fl.glu` -- see that module's own doc
 * comment.
 *
 * **Callback shape**: GLUT's own C API is genuinely "register a plain
 * function pointer" (`void (*f)()`, no closure/context slot at all) --
 * unlike this port's own `Callback = void delegate(Widget)` convention
 * for FLTK's *own* widget callbacks (CONVENTIONS.md's established delegate-
 * over-function-pointer substitution), `GlutWindow`'s per-callback
 * fields below are plain D `function` pointers, matching FLTK's
 * real shape exactly -- a GLUT program's `glutDisplayFunc(&display)`
 * call needs a plain function to pass, not a delegate, so faithfully
 * matching the C shape here is the *correct* port, not a missed
 * modernization.
 *
 * **Menu item callbacks bridge into this port's real `Callback` type at
 * `glutAddMenuEntry()`/`glutAddSubMenu()` time**, via a closure that
 * captures the per-item `int value` and the whole menu's `void
 * function(int)` callback directly -- cleaner than FLTK's own
 * `Fl_Menu_Item::callback_`-field type-punning hack (storing a
 * `void(*)(int)` cast through `Fl_Callback*`, then casting back and
 * calling with `int(g->argument())` at `domenu()` time), which exists
 * in C++ purely because there's no closure to capture the value in
 * instead. `MenuItem` has no `user_data_`/`argument()` slot to smuggle
 * anything through in this port to begin with (see `fl.menu_item`'s own
 * doc comment on why) -- a real difference this rewrite needs, not an
 * arbitrary one.
 *
 * **Timer/idle callbacks bridge into `fl.core.addTimeout()`/`addIdle()`**
 * (delegate-based) the same way: `glutTimerFunc()`'s closure captures
 * its own `value` directly. `glutIdleFunc()`'s FLTK dedup-by-
 * identity logic (`if (glut_idle_func == f) return;` /
 * `Fl::remove_idle(...)`) needs a *stable*, `is`-comparable delegate to
 * pass to `fl.core.removeIdle()` later -- a fresh closure literal
 * evaluated twice is never `is`-equal to itself in D even for
 * functionally-identical captures, so a private singleton trampoline
 * object's bound method (`&idleTrampoline_.run`, stable across calls
 * for the same instance) stands in for FLTK's raw function pointer
 * comparison.
 *
 * **`Fl_Screen_Driver::scale_handler()`'s ctrl+/-/0 window-scaling
 * shortcut check, inside `Fl_Glut_Window::handle()`'s keyboard case, is
 * not reproduced** -- this port has no independent per-screen scale-
 * factor mechanism at all (`GlWindow.pixelsPerUnit()` is always `1`,
 * see that module's own doc comment), so the branch it guards is
 * inherently inapplicable here, not a cut corner.
 *
 * **`glutInit(string[] args)` takes `args` by value**, not FLTK's
 * mutable-in-place `int*, char**` pair -- none of this port's own
 * GLUT-based samples read a filtered `args` back after calling
 * `glutInit()` (checked directly: all three call it once and move
 * straight to window creation), so the in-place-filtering half of
 * FLTK's behavior isn't reproduced. The half that *does* matter --
 * making FLTK's own recognized switches (geometry, `-scheme`, etc.)
 * reach the very first `glutCreateWindow()`'s own `show(args)` call --
 * is: `args` is saved internally and handed to that first window's
 * `show()` exactly once, matching FLTK's own `if (initargc) {
 * W->show(initargc,initargv); initargc=0; } else W->show();` exactly.
 *
 * **GLUT_CURSOR_* constants**: some map onto this port's own named
 * `fl.enumerations.Cursor` members (`GLUT_CURSOR_WAIT` -> `Cursor.wait`,
 * etc); five (`RIGHT_ARROW`/`LEFT_ARROW`/`DESTROY`/`CYCLE`/`SPRAY`) are
 * raw X11 cursor-font glyph indices with no named equivalent in this
 * port either, matching FLTK's own doc comment right above them
 * ("notice that the numeric values are different than glut") -- ported
 * as `cast(Cursor)` literals of the same raw numbers FLTK uses.
 */
module fl.glut;

version (linux) version = FldtkGlut;
version (Windows) version = FldtkGlut;

version (FldtkGlut):

import fl.gl_window : GlWindow;
import fl.window : Window;
import fl.widget : Widget, Callback;
import fl.group : FlGroup;
import fl.menu_item : MenuItem, MenuFlags, menuSubmenuPointer;
import fl.menu_popup : popup;
import fl.enumerations : Event, Cursor, Damage,
    modeRgb, modeIndex, modeSingle, modeDouble, modeAccum, modeAlpha,
    modeDepth, modeStencil, modeMultisample, modeStereo,
    left, up, right, down, pageUp, pageDown, home, end, insert, f, fLast;
import fl.opengl : GLenum, GLint, glGetIntegerv, glGetString, GL_EXTENSIONS,
    GL_RED_BITS, GL_GREEN_BITS, GL_BLUE_BITS, GL_ALPHA_BITS, GL_DEPTH_BITS,
    GL_STENCIL_BITS, GL_ACCUM_RED_BITS, GL_ACCUM_GREEN_BITS,
    GL_ACCUM_BLUE_BITS, GL_ACCUM_ALPHA_BITS, GL_INDEX_BITS, GL_DOUBLEBUFFER,
    GL_STEREO, GL_SAMPLES, GL_RGBA;
import glDriver = fl.gl_window_driver;
import fl.core;

import std.string : fromStringz;

// ---------------------------------------------------------------------
// Fl_Glut_Window
// ---------------------------------------------------------------------

alias GlutDisplayFunc = void function();
alias GlutReshapeFunc = void function(int w, int h);
alias GlutKeyboardFunc = void function(ubyte key, int x, int y);
alias GlutMouseFunc = void function(int b, int state, int x, int y);
alias GlutMotionFunc = void function(int x, int y);
alias GlutPassiveMotionFunc = void function(int x, int y);
alias GlutEntryFunc = void function(int s);
alias GlutVisibilityFunc = void function(int s);
alias GlutSpecialFunc = void function(int key, int x, int y);
alias GlutMenuCallback = void function(int value);
alias GlutMenuStateFunc = void function(int state);
alias GlutMenuStatusFunc = void function(int status, int x, int y);
alias GlutTimerFunc = void function(int value);

private enum maxWindows = 32;
private GlutWindow[maxWindows + 1] windows_;

private void defaultReshape(int w, int h) { glViewport(0, 0, w, h); }
private void defaultDisplay() { }

/// The current GLUT window, or `null` -- ported from FLTK's global
/// `Fl_Glut_Window *glut_window`. Referenced directly (not just through
/// `glutGetWindow()`) by real FLTK samples, e.g. `test/fractals.cxx`'s
/// `window.resizable(glut_window)` right after `glutCreateWindow()`.
GlutWindow glutWindow;

private int glutMenuNum_; // matches FLTK's `int glut_menu`
GlutMenuStateFunc glutMenustateFunction;
GlutMenuStatusFunc glutMenustatusFunction;

class GlutWindow : GlWindow
{
    package(fl) int number;
    package(fl) int[3] menu;
    private int mouseDown_;

    GlutDisplayFunc display;
    GlutDisplayFunc overlaydisplay;
    GlutReshapeFunc reshape;
    GlutKeyboardFunc keyboard;
    GlutMouseFunc mouse;
    GlutMotionFunc motion;
    GlutPassiveMotionFunc passivemotion;
    GlutEntryFunc entry;
    GlutVisibilityFunc visibility;
    GlutSpecialFunc special;

    private void init_()
    {
        int n;
        for (n = 1; n < maxWindows; n++)
            if (windows_[n] is null) break;
        number = n;
        windows_[n] = this;
        menu[0] = menu[1] = menu[2] = 0;
        reshape = &defaultReshape;
        display = &defaultDisplay;
        overlaydisplay = &defaultDisplay;
        mode(glutMode_);
    }

    /// Creates a glut window, registers it in the glut windows list.
    this(int w, int h, string t = null)
    {
        super(w, h, t);
        init_();
    }

    /// ditto
    this(int x, int y, int w, int h, string t = null)
    {
        super(x, y, w, h, t);
        init_();
    }

    ~this()
    {
        import core.memory : GC;

        // See CONVENTIONS.md's GC-finalizer-hazard note: touching other
        // GC-managed state (the module-level windows_/glutWindow
        // globals) from a finalizer running during a GC sweep is unsafe.
        if (GC.inFinalizer()) return;
        if (glutWindow is this) glutWindow = null;
        if (number >= 0 && number < windows_.length) windows_[number] = null;
    }

    override void makeCurrent()
    {
        glutWindow = this;
        if (shown()) super.makeCurrent();
    }

    override void draw()
    {
        glutWindow = this;
        indraw_ = true;
        if (!valid())
        {
            reshape(pixelW(), pixelH());
            valid(true);
        }
        display();
        if (children())
            super.draw(); // Draw FLTK child widgets.
        indraw_ = false;
    }

    override void drawOverlay()
    {
        glutWindow = this;
        if (!valid())
        {
            reshape(pixelW(), pixelH());
            valid(true);
        }
        overlaydisplay();
    }

    override int handle(Event event)
    {
        makeCurrent();
        int ex = fl.core.eventX();
        int ey = fl.core.eventY();
        float factor = pixelsPerUnit();
        ex = cast(int)(ex * factor + 0.5f);
        ey = cast(int)(ey * factor + 0.5f);
        int button;
        switch (event)
        {
        case Event.push:
            if (keyboard || special) fl.core.focus(this);
            button = fl.core.eventButton() - 1;
            if (button < 0) button = 0;
            if (button > 2) button = 2;
            if (menu[button]) { domenu(menu[button], ex, ey); return 1; }
            mouseDown_ |= 1 << button;
            if (mouse) { mouse(button, GLUT_DOWN, ex, ey); return 1; }
            if (motion) return 1;
            break;

        case Event.mouseWheel:
            button = fl.core.eventDy();
            while (button < 0) { if (mouse) mouse(3, GLUT_DOWN, ex, ey); ++button; }
            while (button > 0) { if (mouse) mouse(4, GLUT_DOWN, ex, ey); --button; }
            return 1;

        case Event.release:
            for (button = 0; button < 3; button++)
                if (mouseDown_ & (1 << button))
                    if (mouse) mouse(button, GLUT_UP, ex, ey);
            mouseDown_ = 0;
            return 1;

        case Event.enter:
            if (entry) { entry(GLUT_ENTERED); return 1; }
            if (passivemotion) return 1;
            break;

        case Event.leave:
            if (entry) { entry(GLUT_LEFT); return 1; }
            if (passivemotion) return 1;
            break;

        case Event.drag:
            if (motion) { motion(ex, ey); return 1; }
            break;

        case Event.move:
            if (passivemotion) { passivemotion(ex, ey); return 1; }
            break;

        case Event.focus:
            if (keyboard || special) return 1;
            break;

        case Event.shortcut:
            if (!keyboard && !special) break;
            goto case Event.keyDown;

        case Event.keyDown:
            if (fl.core.eventText().length > 0)
            {
                if (keyboard) { keyboard(cast(ubyte) fl.core.eventText()[0], ex, ey); return 1; }
                break;
            }
            else
            {
                if (special)
                {
                    int k = fl.core.eventKey();
                    if (k > f && k <= fLast) k -= f;
                    special(k, ex, ey);
                    return 1;
                }
                break;
            }

        case Event.hide:
            if (visibility) visibility(GLUT_NOT_VISIBLE);
            break;

        case Event.show:
            if (visibility) visibility(GLUT_VISIBLE);
            break;

        default:
            break;
        }

        return super.handle(event);
    }
}

/// True while `GlutWindow.draw()` is running -- ported from FLTK's
/// file-static `int indraw` (a single shared flag, not per-window,
/// matching FLTK's own shape exactly), consulted by `glutSwapBuffers()`
/// below (a plain-immediate-mode GLUT program calls it explicitly at the
/// end of its own `display` callback; calling it *during* `draw()` --
/// FLTK's `Fl_Gl_Window::flush()` already swaps automatically once
/// `display()` returns -- would double-swap).
private bool indraw_;

private import fl.opengl : glViewport;

// ---------------------------------------------------------------------
// Initialization / main loop
// ---------------------------------------------------------------------

private int glutMode_ = modeRgb | modeSingle | modeDepth;
private string[] glutInitArgs_;

/// Ported from `glutInit(int*, char**)` -- see this module's own top
/// comment for why the in-place `argc`/`argv` filtering isn't
/// reproduced (no call site in this port's sample tree needs it back).
void glutInit(string[] args)
{
    glutInitArgs_ = args;
}

void glutInitDisplayMode(uint mode)
{
    glutMode_ = mode;
}

// The FL_ symbols have the same value as the GLUT ones (`FL/Enumerations.H`'s
// own doc comment: "values match Glut") -- ported straight from
// `FL/glut.H`'s own `#define GLUT_RGB FL_RGB` etc, just aliasing this
// port's already-real `fl.enumerations` mode constants instead of FLTK's
// C++ `FL_*` names.
enum GLUT_RGB = modeRgb;
enum GLUT_RGBA = modeRgb;
enum GLUT_INDEX = modeIndex;
enum GLUT_SINGLE = modeSingle;
enum GLUT_DOUBLE = modeDouble;
enum GLUT_ACCUM = modeAccum;
enum GLUT_ALPHA = modeAlpha;
enum GLUT_DEPTH = modeDepth;
enum GLUT_STENCIL = modeStencil;
enum GLUT_MULTISAMPLE = modeMultisample;
enum GLUT_STEREO = modeStereo;

void glutMainLoop()
{
    fl.core.run();
}

// ---------------------------------------------------------------------
// Window management
// ---------------------------------------------------------------------

private int initX_, initY_, initW_ = 300, initH_ = 300;
private bool initPos_;

void glutInitWindowPosition(int x, int y)
{
    initX_ = x;
    initY_ = y;
    initPos_ = true;
}

void glutInitWindowSize(int w, int h)
{
    initW_ = w;
    initH_ = h;
}

int glutCreateWindow(string title)
{
    GlutWindow w;
    if (initPos_)
    {
        w = new GlutWindow(initX_, initY_, initW_, initH_, title);
        initPos_ = false;
    }
    else
    {
        w = new GlutWindow(initW_, initH_, title);
    }
    w.resizable(w);
    if (glutInitArgs_.length > 0)
    {
        w.show(glutInitArgs_);
        glutInitArgs_ = null;
    }
    else
    {
        w.show();
    }
    w.valid(false);
    w.contextValid(false);
    w.makeCurrent();
    w.redraw();
    return w.number;
}

int glutCreateSubWindow(int win, int x, int y, int w, int h)
{
    auto sub = new GlutWindow(x, y, w, h, null);
    windows_[win].add(sub);
    if (windows_[win].shown())
    {
        sub.show();
        sub.makeCurrent();
        sub.redraw();
    }
    return sub.number;
}

void glutDestroyWindow(int win)
{
    destroy(windows_[win]);
}

void glutPostWindowRedisplay(int win)
{
    windows_[win].redraw();
}

void glutSwapBuffers()
{
    if (!indraw_ && glutWindow !is null) glutWindow.swapBuffers();
}

int glutGetWindow()
{
    return glutWindow !is null ? glutWindow.number : 0;
}

void glutSetWindow(int win)
{
    windows_[win].makeCurrent();
}

void glutPostRedisplay()
{
    if (glutWindow !is null) glutWindow.redraw();
}

void glutSetWindowTitle(string t)
{
    if (glutWindow !is null) glutWindow.label(t);
}

void glutSetIconTitle(string t)
{
    if (glutWindow !is null) glutWindow.iconlabel(t);
}

void glutPositionWindow(int x, int y)
{
    if (glutWindow !is null) glutWindow.position(x, y);
}

void glutReshapeWindow(int w, int h)
{
    if (glutWindow !is null) glutWindow.size(w, h);
}

void glutPopWindow()
{
    if (glutWindow !is null) glutWindow.show();
}

void glutPushWindow()
{
    // Matches FLTK's own no-op body exactly.
}

void glutIconifyWindow()
{
    if (glutWindow !is null) glutWindow.iconize();
}

void glutShowWindow()
{
    if (glutWindow !is null) glutWindow.show();
}

void glutHideWindow()
{
    if (glutWindow !is null) glutWindow.hide();
}

void glutFullScreen()
{
    if (glutWindow !is null) glutWindow.fullscreen();
}

void glutSetCursor(Cursor cursor)
{
    if (glutWindow !is null) glutWindow.cursor(cursor);
}

// Notice that the numeric values differ from real GLUT -- matches
// FLTK's own doc comment right above the equivalent block in
// `FL/glut.H` verbatim; see this module's own top comment.
enum Cursor GLUT_CURSOR_RIGHT_ARROW = cast(Cursor) 2;
enum Cursor GLUT_CURSOR_LEFT_ARROW = cast(Cursor) 67;
enum Cursor GLUT_CURSOR_INFO = Cursor.hand;
enum Cursor GLUT_CURSOR_DESTROY = cast(Cursor) 45;
enum Cursor GLUT_CURSOR_HELP = Cursor.help;
enum Cursor GLUT_CURSOR_CYCLE = cast(Cursor) 26;
enum Cursor GLUT_CURSOR_SPRAY = cast(Cursor) 63;
enum Cursor GLUT_CURSOR_WAIT = Cursor.wait;
enum Cursor GLUT_CURSOR_TEXT = Cursor.insert;
enum Cursor GLUT_CURSOR_CROSSHAIR = Cursor.cross;
enum Cursor GLUT_CURSOR_UP_DOWN = Cursor.ns;
enum Cursor GLUT_CURSOR_LEFT_RIGHT = Cursor.we;
enum Cursor GLUT_CURSOR_TOP_SIDE = Cursor.n;
enum Cursor GLUT_CURSOR_BOTTOM_SIDE = Cursor.s;
enum Cursor GLUT_CURSOR_LEFT_SIDE = Cursor.w;
enum Cursor GLUT_CURSOR_RIGHT_SIDE = Cursor.e;
enum Cursor GLUT_CURSOR_TOP_LEFT_CORNER = Cursor.nw;
enum Cursor GLUT_CURSOR_TOP_RIGHT_CORNER = Cursor.ne;
enum Cursor GLUT_CURSOR_BOTTOM_RIGHT_CORNER = Cursor.se;
enum Cursor GLUT_CURSOR_BOTTOM_LEFT_CORNER = Cursor.sw;
enum Cursor GLUT_CURSOR_INHERIT = Cursor.default_;
enum Cursor GLUT_CURSOR_NONE = Cursor.none;
enum Cursor GLUT_CURSOR_FULL_CROSSHAIR = Cursor.cross;

void glutWarpPointer(int, int)
{
    // Matches FLTK's own no-op body exactly.
}

void glutEstablishOverlay()
{
    if (glutWindow !is null) glutWindow.makeOverlayCurrent();
}

void glutRemoveOverlay()
{
    if (glutWindow !is null) glutWindow.hideOverlay();
}

enum GLUT_NORMAL = 0;
enum GLUT_OVERLAY = 1;

void glutUseLayer(GLenum layer)
{
    if (glutWindow is null) return;
    if (layer) glutWindow.makeOverlayCurrent();
    else glutWindow.makeCurrent();
}

void glutPostOverlayRedisplay()
{
    if (glutWindow !is null) glutWindow.redrawOverlay();
}

void glutShowOverlay()
{
    if (glutWindow !is null) glutWindow.redrawOverlay();
}

void glutHideOverlay()
{
    if (glutWindow !is null) glutWindow.hideOverlay();
}

// ---------------------------------------------------------------------
// Menus
// ---------------------------------------------------------------------

private enum maxMenus = 32;

private struct GlutMenu
{
    GlutMenuCallback cb;
    MenuItem[] items; // always ends with a null-text sentinel once non-empty
}

private GlutMenu[maxMenus + 1] menus_;

/// Ported from `additem()` (`src/glut_compatibility.cxx`): appends
/// `item`, keeping a trailing null-text sentinel one past the last real
/// entry at all times -- matches FLTK's own `m->m[n+1].text = 0;`
/// discipline, needed since `MenuItem*` array-walking code elsewhere in
/// this port (`fl.menu_popup`) finds the end of an array via that
/// sentinel, not a separately-tracked length. Returns the new item's
/// 1-based index, matching `glutChangeToMenuEntry()`/`glutRemoveMenuItem()`'s
/// own 1-based `item` parameter.
private int addItem(ref GlutMenu m, MenuItem item)
{
    if (m.items.length == 0) m.items = [MenuItem(null)];
    m.items[$ - 1] = item;
    m.items ~= MenuItem(null);
    return cast(int) m.items.length - 1;
}

private void domenu(int n, int ex, int ey)
{
    glutMenuNum_ = n;
    auto m = &menus_[n];
    if (glutMenustateFunction) glutMenustateFunction(1);
    if (glutMenustatusFunction) glutMenustatusFunction(1, ex, ey);
    const(MenuItem)* g = popup(m.items.ptr, fl.core.eventXRoot(), fl.core.eventYRoot());
    if (g !is null && g.callback_ !is null) g.callback_(null);
    if (glutMenustatusFunction) glutMenustatusFunction(0, ex, ey);
    if (glutMenustateFunction) glutMenustateFunction(0);
}

int glutCreateMenu(GlutMenuCallback cb)
{
    int i;
    for (i = 1; i < maxMenus; i++)
        if (menus_[i].cb is null) break;
    menus_[i] = GlutMenu(cb, null);
    return glutMenuNum_ = i;
}

void glutDestroyMenu(int n)
{
    menus_[n] = GlutMenu.init;
}

int glutGetMenu()
{
    return glutMenuNum_;
}

void glutSetMenu(int m)
{
    glutMenuNum_ = m;
}

void glutAddMenuEntry(string label, int value)
{
    auto m = &menus_[glutMenuNum_];
    GlutMenuCallback cb = m.cb;
    addItem(*m, MenuItem(label, 0, (Widget w) { if (cb) cb(value); }, 0));
}

void glutAddSubMenu(string label, int submenu)
{
    auto m = &menus_[glutMenuNum_];
    if (menus_[submenu].items.length == 0) menus_[submenu].items = [MenuItem(null)];
    addItem(*m, MenuItem(label, 0, null, menuSubmenuPointer, &menus_[submenu].items[0]));
}

void glutChangeToMenuEntry(int item, string label, int value)
{
    auto m = &menus_[glutMenuNum_];
    GlutMenuCallback cb = m.cb;
    m.items[item - 1] = MenuItem(label, 0, (Widget w) { if (cb) cb(value); }, 0);
}

void glutChangeToSubMenu(int item, string label, int submenu)
{
    auto m = &menus_[glutMenuNum_];
    if (menus_[submenu].items.length == 0) menus_[submenu].items = [MenuItem(null)];
    m.items[item - 1] = MenuItem(label, 0, null, menuSubmenuPointer, &menus_[submenu].items[0]);
}

void glutRemoveMenuItem(int item)
{
    auto m = &menus_[glutMenuNum_];
    if (item > cast(int) m.items.length - 1 || item < 1) return;
    m.items = m.items[0 .. item - 1] ~ m.items[item .. $];
}

void glutAttachMenu(int b)
{
    if (glutWindow !is null) glutWindow.menu[b] = glutMenuNum_;
}

void glutDetachMenu(int b)
{
    if (glutWindow !is null) glutWindow.menu[b] = 0;
}

// ---------------------------------------------------------------------
// Callback registration
// ---------------------------------------------------------------------

void glutDisplayFunc(GlutDisplayFunc f)
{
    if (glutWindow !is null) glutWindow.display = f;
}

void glutReshapeFunc(GlutReshapeFunc f)
{
    if (glutWindow !is null) glutWindow.reshape = f;
}

void glutKeyboardFunc(GlutKeyboardFunc f)
{
    if (glutWindow !is null) glutWindow.keyboard = f;
}

void glutMouseFunc(GlutMouseFunc f)
{
    if (glutWindow !is null) glutWindow.mouse = f;
}

enum GLUT_LEFT_BUTTON = 0;
enum GLUT_MIDDLE_BUTTON = 1;
enum GLUT_RIGHT_BUTTON = 2;
enum GLUT_DOWN = 0;
enum GLUT_UP = 1;

void glutMotionFunc(GlutMotionFunc f)
{
    if (glutWindow !is null) glutWindow.motion = f;
}

void glutPassiveMotionFunc(GlutPassiveMotionFunc f)
{
    if (glutWindow !is null) glutWindow.passivemotion = f;
}

void glutEntryFunc(GlutEntryFunc f)
{
    if (glutWindow !is null) glutWindow.entry = f;
}

enum GLUT_LEFT = 0;
enum GLUT_ENTERED = 1;

void glutVisibilityFunc(GlutVisibilityFunc f)
{
    if (glutWindow !is null) glutWindow.visibility = f;
}

enum GLUT_NOT_VISIBLE = 0;
enum GLUT_VISIBLE = 1;

/// Backs `glutIdleFunc()`'s FLTK dedup-by-identity semantics -- see
/// this module's own top comment for why a stable, `is`-comparable
/// bound-method delegate is needed instead of a fresh closure literal.
private final class IdleTrampoline
{
    void run()
    {
        if (glutIdleFuncPtr_) glutIdleFuncPtr_();
    }
}

private IdleTrampoline idleTrampoline_;
private GlutDisplayFunc glutIdleFuncPtr_; // matches FLTK's `glut_idle_func`

void glutIdleFunc(GlutDisplayFunc f)
{
    if (glutIdleFuncPtr_ == f) return;
    if (idleTrampoline_ is null) idleTrampoline_ = new IdleTrampoline();
    if (glutIdleFuncPtr_) fl.core.removeIdle(&idleTrampoline_.run);
    if (f) fl.core.addIdle(&idleTrampoline_.run);
    glutIdleFuncPtr_ = f;
}

void glutTimerFunc(uint msec, GlutTimerFunc f, int value)
{
    fl.core.addTimeout(msec * 0.001, () { f(value); });
}

void glutMenuStateFunc(GlutMenuStateFunc f)
{
    glutMenustateFunction = f;
}

void glutMenuStatusFunc(GlutMenuStatusFunc f)
{
    glutMenustatusFunction = f;
}

enum GLUT_MENU_NOT_IN_USE = 0;
enum GLUT_MENU_IN_USE = 1;

void glutSpecialFunc(GlutSpecialFunc f)
{
    if (glutWindow !is null) glutWindow.special = f;
}

enum GLUT_KEY_F1 = 1;
enum GLUT_KEY_F2 = 2;
enum GLUT_KEY_F3 = 3;
enum GLUT_KEY_F4 = 4;
enum GLUT_KEY_F5 = 5;
enum GLUT_KEY_F6 = 6;
enum GLUT_KEY_F7 = 7;
enum GLUT_KEY_F8 = 8;
enum GLUT_KEY_F9 = 9;
enum GLUT_KEY_F10 = 10;
enum GLUT_KEY_F11 = 11;
enum GLUT_KEY_F12 = 12;
// Warning: different values than real GLUT uses, matching FLTK's
// own doc comment -- these are this port's fl.enumerations Keysym
// values directly.
enum GLUT_KEY_LEFT = left;
enum GLUT_KEY_UP = up;
enum GLUT_KEY_RIGHT = right;
enum GLUT_KEY_DOWN = down;
enum GLUT_KEY_PAGE_UP = pageUp;
enum GLUT_KEY_PAGE_DOWN = pageDown;
enum GLUT_KEY_HOME = home;
enum GLUT_KEY_END = end;
enum GLUT_KEY_INSERT = insert;

void glutOverlayDisplayFunc(GlutDisplayFunc f)
{
    if (glutWindow !is null) glutWindow.overlaydisplay = f;
}

// ---------------------------------------------------------------------
// glutGet() / glutLayerGet() / glutDeviceGet()
// ---------------------------------------------------------------------

// Warning: values differ from real GLUT, matching FLTK's own doc
// comment -- also relies on the GL_* symbols having values greater than
// 100, same as FLTK.
enum
{
    GLUT_RETURN_ZERO = 0,
    GLUT_WINDOW_X,
    GLUT_WINDOW_Y,
    GLUT_WINDOW_WIDTH,
    GLUT_WINDOW_HEIGHT,
    GLUT_WINDOW_PARENT,
    GLUT_SCREEN_WIDTH,
    GLUT_SCREEN_HEIGHT,
    GLUT_MENU_NUM_ITEMS,
    GLUT_DISPLAY_MODE_POSSIBLE,
    GLUT_INIT_WINDOW_X,
    GLUT_INIT_WINDOW_Y,
    GLUT_INIT_WINDOW_WIDTH,
    GLUT_INIT_WINDOW_HEIGHT,
    // Named `GLUT_INIT_DISPLAY_MODE`, not `glutInitDisplayMode` (FLTK's
    // literal `GLUT_INIT_DISPLAY_MODE`) -- that spelling collides with the
    // `glutInitDisplayMode(uint)` *function* above once both are lowered
    // to this port's camelCase convention (FLTK keeps them apart via
    // ALL_CAPS-vs-camelCase, a distinction that doesn't survive the
    // convention change).
    GLUT_INIT_DISPLAY_MODE,
    GLUT_WINDOW_BUFFER_SIZE,
    GLUT_VERSION,
    GLUT_ELAPSED_TIME,
}

enum GLUT_WINDOW_STENCIL_SIZE = GL_STENCIL_BITS;
enum GLUT_WINDOW_DEPTH_SIZE = GL_DEPTH_BITS;
enum GLUT_WINDOW_RED_SIZE = GL_RED_BITS;
enum GLUT_WINDOW_GREEN_SIZE = GL_GREEN_BITS;
enum GLUT_WINDOW_BLUE_SIZE = GL_BLUE_BITS;
enum GLUT_WINDOW_ALPHA_SIZE = GL_ALPHA_BITS;
enum GLUT_WINDOW_ACCUM_RED_SIZE = GL_ACCUM_RED_BITS;
enum GLUT_WINDOW_ACCUM_GREEN_SIZE = GL_ACCUM_GREEN_BITS;
enum GLUT_WINDOW_ACCUM_BLUE_SIZE = GL_ACCUM_BLUE_BITS;
enum GLUT_WINDOW_ACCUM_ALPHA_SIZE = GL_ACCUM_ALPHA_BITS;
enum GLUT_WINDOW_DOUBLEBUFFER = GL_DOUBLEBUFFER;
enum GLUT_WINDOW_RGBA = GL_RGBA;
enum GLUT_WINDOW_COLORMAP_SIZE = GL_INDEX_BITS;
enum GLUT_WINDOW_NUM_SAMPLES = GL_SAMPLES;
enum GLUT_WINDOW_STEREO = GL_STEREO;

enum GLUT_HAS_KEYBOARD = 600;
enum GLUT_HAS_MOUSE = 601;
enum GLUT_NUM_MOUSE_BUTTONS = 603;

private Timestamp glutStarttime_;
private bool glutStarttimeSet_;

private void ensureStarttime()
{
    if (!glutStarttimeSet_)
    {
        glutStarttime_ = fl.core.now();
        glutStarttimeSet_ = true;
    }
}

int glutGet(GLenum type)
{
    switch (type)
    {
    case GLUT_RETURN_ZERO: return 0;
    case GLUT_WINDOW_X: return glutWindow ? glutWindow.x() : 0;
    case GLUT_WINDOW_Y: return glutWindow ? glutWindow.y() : 0;
    case GLUT_WINDOW_WIDTH: return glutWindow ? glutWindow.pixelW() : 0;
    case GLUT_WINDOW_HEIGHT: return glutWindow ? glutWindow.pixelH() : 0;
    case GLUT_WINDOW_PARENT:
        if (glutWindow !is null && glutWindow.parent() !is null)
            return (cast(GlutWindow) glutWindow.parent()).number;
        else
            return 0;
    case GLUT_SCREEN_WIDTH:
    {
        int x, y, w, h;
        fl.core.screenXYWH(x, y, w, h);
        return w;
    }
    case GLUT_SCREEN_HEIGHT:
    {
        int x, y, w, h;
        fl.core.screenXYWH(x, y, w, h);
        return h;
    }
    case GLUT_MENU_NUM_ITEMS:
    {
        int len = cast(int) menus_[glutMenuNum_].items.length;
        return len ? len - 1 : 0;
    }
    case GLUT_DISPLAY_MODE_POSSIBLE: return GlWindow.canDo(glutMode_);
    case GLUT_INIT_WINDOW_X: return initX_;
    case GLUT_INIT_WINDOW_Y: return initY_;
    case GLUT_INIT_WINDOW_WIDTH: return initW_;
    case GLUT_INIT_WINDOW_HEIGHT: return initH_;
    case GLUT_INIT_DISPLAY_MODE: return glutMode_;
    case GLUT_ELAPSED_TIME:
        ensureStarttime();
        return cast(int)(fl.core.secondsSince(glutStarttime_) * 1000.0);
    case GLUT_WINDOW_BUFFER_SIZE:
        if (glutGet(GLUT_WINDOW_RGBA))
            return glutGet(GLUT_WINDOW_RED_SIZE) + glutGet(GLUT_WINDOW_GREEN_SIZE)
                + glutGet(GLUT_WINDOW_BLUE_SIZE) + glutGet(GLUT_WINDOW_ALPHA_SIZE);
        else
            return glutGet(GLUT_WINDOW_COLORMAP_SIZE);
    case GLUT_VERSION: return 20400;
    default:
        GLint p;
        glGetIntegerv(type, &p);
        return p;
    }
}

int glutLayerGet(GLenum type)
{
    switch (type)
    {
    case GLUT_OVERLAY_POSSIBLE: return glutWindow ? glutWindow.canDoOverlay() : 0;
    case GLUT_TRANSPARENT_INDEX: return 0; // true for SGI
    case GLUT_NORMAL_DAMAGED: return glutWindow ? glutWindow.damage() : 0;
    case GLUT_OVERLAY_DAMAGED: return 1; // kind of works...
    default: return 0;
    }
}

enum GLUT_OVERLAY_POSSIBLE = 800;
enum GLUT_LAYER_IN_USE = 801;
enum GLUT_HAS_OVERLAY = 802;
enum GLUT_TRANSPARENT_INDEX = 803;
enum GLUT_NORMAL_DAMAGED = 804;
enum GLUT_OVERLAY_DAMAGED = 805;

int glutDeviceGet(GLenum type)
{
    switch (type)
    {
    case GLUT_HAS_KEYBOARD: return 1;
    case GLUT_HAS_MOUSE: return 1;
    case GLUT_NUM_MOUSE_BUTTONS: return 3;
    default: return 0;
    }
}

alias GLUTproc = void function();

/// Ported from `glutGetProcAddress()` -- FLTK routes through
/// `Fl_Gl_Window_Driver::global()->GetProcAddress()`; this port's own
/// driver model is a plain module of free functions (see
/// `fl.gl_window_driver`'s own doc comment on why), so this calls
/// straight through to `fl.gl_window_driver.getProcAddress()`.
GLUTproc glutGetProcAddress(string procName)
{
    import std.string : toStringz;

    return cast(GLUTproc) glDriver.getProcAddress(procName.toStringz);
}

/// Ported from `glutExtensionSupported()`, itself copied by FLTK
/// from FreeGLUT 2.4.0 -- a plain substring-with-word-boundary scan
/// over `glGetString(GL_EXTENSIONS)`.
bool glutExtensionSupported(string extension)
{
    import std.string : indexOf;

    if (extension.length == 0 || extension.indexOf(' ') >= 0) return false;

    const(char)* extPtr = cast(const(char)*) glGetString(GL_EXTENSIONS);
    if (extPtr is null) return false;
    string extensions = cast(string) fromStringz(extPtr);

    size_t pos = 0;
    while (true)
    {
        auto p = extensions[pos .. $].indexOf(extension);
        if (p < 0) return false;
        p += pos;
        bool leftOk = (p == 0 || extensions[p - 1] == ' ');
        size_t after = p + extension.length;
        bool rightOk = (after == extensions.length || extensions[after] == ' ');
        if (leftOk && rightOk) return true;
        pos = after;
    }
}
