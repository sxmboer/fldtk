/*
 * Ported from FL/Fl_Sys_Menu_Bar.H + src/Fl_Sys_Menu_Bar.cxx (FLTK
 * 1.5.0): a menu bar that, on macOS, integrates with the native system
 * application menu bar instead of drawing its own row inside the FLTK
 * window.
 *
 * Every instance method FLTK defines follows the same shape:
 * `if (driver()) driver()->X(...); else Fl_Menu_Bar::X(...);` -- i.e.
 * the native-menu-bar behavior only exists when a
 * `Fl_Sys_Menu_Bar_Driver` (macOS-only, `src/drivers/Cocoa/
 * Fl_MacOS_Sys_Menu_Bar_Driver.H`) is active; otherwise every method
 * degenerates to plain `Fl_Menu_Bar` behavior. Since this port has no
 * macOS driver at all (see `PORTING.md`'s `FL/mac.H` row -- "out of
 * scope for testing"), `driver()` is permanently null here, so *every*
 * one of those overridden instance methods (`menu()`, `shortcut()`,
 * `setonly()`, `mode()`, `add()`, `insert()`, `clear()`,
 * `clear_submenu()`, `remove()`, `replace()`, `update()`,
 * `play_menu()`, `draw()`) would just forward straight to its
 * `Fl_Menu_Bar`/`Menu_` base-class version with zero behavior added --
 * this port skips writing that dead always-else branch out for each of
 * them and simply doesn't override any of them at all, letting `MenuBar`
 * (`fl.menu_bar`) handle every one for free through ordinary
 * inheritance. Only the genuinely Mac-only surface is ported:
 * `about()` (a real, if permanently inert, no-op on this platform --
 * its own FLTK doc comment says "effective only under the MacOS
 * platform") and `isGlobal()` (always `false` with no driver, since a
 * `Fl_Sys_Menu_Bar` is never "global" without native integration).
 * `windowMenuStyle()`/`createWindowMenu()` aren't ported -- genuinely
 * macOS-only static configuration for a feature (the native Window
 * menu) that has no effect at all without a driver, and nothing in
 * this port's samples calls them uncommented.
 */
module fl.sys_menu_bar;

import fl.menu_bar : MenuBar;
import fl.widget : Callback;

class SysMenuBar : MenuBar
{
    this(int x, int y, int w, int h, string label = null)
    {
        super(x, y, w, h, label);
    }

    /// Ported from `Fl_Sys_Menu_Bar::about(Fl_Callback*, void*)` --
    /// "effective only under the MacOS platform" per its own FLTK
    /// doc comment; a genuine no-op here, not a simplification (no
    /// driver exists to route this to). The `void* data` parameter
    /// FLTK also takes has no equivalent (see CONVENTIONS.md's
    /// callback-porting convention -- a delegate already carries its
    /// own captured state).
    static void about(Callback cb) { }

    /// Ported from `Fl_Sys_Menu_Bar::is_global()`: "true if the menu
    /// bar is located at the top of the desktop window" -- always
    /// `false` here, since that's only ever true once a driver claims
    /// this bar as the one active system menu bar, and no driver
    /// exists in this port.
    bool isGlobal() const { return false; }
}
