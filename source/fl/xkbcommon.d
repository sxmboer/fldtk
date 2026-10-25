/*
 * `extern(C)` bindings for the part of libxkbcommon that turns Wayland
 * key codes into keysyms and text: contexts, keymaps from a string,
 * keyboard state and its modifiers, and compose (dead keys and compose
 * sequences) -- the functions FLTK's Wayland driver uses
 * (`Fl_Wayland_Screen_Driver.cxx`), from `xkbcommon/xkbcommon.h`,
 * `xkbcommon-compose.h` and `xkbcommon-names.h` (libxkbcommon 1.13).
 * Not the whole API: keymap queries, logging, the keysym name functions
 * and the X11 extension are left out. Infrastructure, like
 * `fl.wayland_client`.
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`).
 */
module fl.xkbcommon;

version (FLDTK_HAVE_WAYLAND):

extern (C) nothrow @nogc:

struct xkb_context;
struct xkb_keymap;
struct xkb_state;
struct xkb_compose_table;
struct xkb_compose_state;

alias xkb_keycode_t = uint;
alias xkb_keysym_t = uint;
alias xkb_layout_index_t = uint;
alias xkb_mod_mask_t = uint;

enum int XKB_CONTEXT_NO_FLAGS = 0;
enum int XKB_KEYMAP_FORMAT_TEXT_V1 = 1;
enum int XKB_KEYMAP_COMPILE_NO_FLAGS = 0;

/// `enum xkb_state_component` bits.
enum int XKB_STATE_MODS_DEPRESSED = 1 << 0;
/// ditto
enum int XKB_STATE_MODS_LATCHED = 1 << 1;
/// ditto
enum int XKB_STATE_MODS_LOCKED = 1 << 2;
/// ditto
enum int XKB_STATE_MODS_EFFECTIVE = 1 << 3;

// xkbcommon-names.h
enum XKB_MOD_NAME_SHIFT = "Shift";
enum XKB_MOD_NAME_CAPS = "Lock";
enum XKB_MOD_NAME_CTRL = "Control";
enum XKB_MOD_NAME_ALT = "Mod1";
enum XKB_MOD_NAME_NUM = "Mod2";
enum XKB_MOD_NAME_LOGO = "Mod4";

xkb_context* xkb_context_new(int flags);
void xkb_context_unref(xkb_context* context);

xkb_keymap* xkb_keymap_new_from_string(xkb_context* context, const(char)* string_, int format, int flags);
void xkb_keymap_unref(xkb_keymap* keymap);

xkb_state* xkb_state_new(xkb_keymap* keymap);
void xkb_state_unref(xkb_state* state);
xkb_keysym_t xkb_state_key_get_one_sym(xkb_state* state, xkb_keycode_t key);
int xkb_state_key_get_utf8(xkb_state* state, xkb_keycode_t key, char* buffer, size_t size);
int xkb_state_update_mask(xkb_state* state, xkb_mod_mask_t depressed_mods, xkb_mod_mask_t latched_mods,
    xkb_mod_mask_t locked_mods, xkb_layout_index_t depressed_layout, xkb_layout_index_t latched_layout,
    xkb_layout_index_t locked_layout);
int xkb_state_mod_name_is_active(xkb_state* state, const(char)* name, int type);

// xkbcommon-compose.h
enum int XKB_COMPOSE_COMPILE_NO_FLAGS = 0;
enum int XKB_COMPOSE_STATE_NO_FLAGS = 0;

/// `enum xkb_compose_status`.
enum : int
{
    XKB_COMPOSE_NOTHING,
    XKB_COMPOSE_COMPOSING,
    XKB_COMPOSE_COMPOSED,
    XKB_COMPOSE_CANCELLED,
}

xkb_compose_table* xkb_compose_table_new_from_locale(xkb_context* context, const(char)* locale, int flags);
void xkb_compose_table_unref(xkb_compose_table* table);
xkb_compose_state* xkb_compose_state_new(xkb_compose_table* table, int flags);
void xkb_compose_state_unref(xkb_compose_state* state);
int xkb_compose_state_feed(xkb_compose_state* state, xkb_keysym_t keysym);
void xkb_compose_state_reset(xkb_compose_state* state);
int xkb_compose_state_get_status(xkb_compose_state* state);
int xkb_compose_state_get_utf8(xkb_compose_state* state, char* buffer, size_t size);
