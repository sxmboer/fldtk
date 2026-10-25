/*
 * `extern(C)` bindings for libwayland-cursor, which loads cursor themes
 * into `wl_shm` buffers: the whole public API of `wayland-cursor.h`
 * (Wayland 1.24). Infrastructure, like `fl.wayland_client`; used by
 * `fl.platform_wayland` when the compositor has no cursor-shape protocol.
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`).
 */
module fl.wayland_cursor;

version (FLDTK_HAVE_WAYLAND):

import fl.wayland_protocol : wl_buffer, wl_shm;

extern (C) nothrow @nogc:

struct wl_cursor_theme;

/// One frame of a cursor.
struct wl_cursor_image
{
    uint width;     /// actual width
    uint height;    /// actual height
    uint hotspot_x; /// hot spot x (inside the image)
    uint hotspot_y; /// hot spot y (inside the image)
    uint delay;     /// animation delay to the next frame, in ms
}

/// A cursor, as a series of images.
struct wl_cursor
{
    uint image_count;
    wl_cursor_image** images;
    char* name;
}

wl_cursor_theme* wl_cursor_theme_load(const(char)* name, int size, wl_shm* shm);
void wl_cursor_theme_destroy(wl_cursor_theme* theme);
wl_cursor* wl_cursor_theme_get_cursor(wl_cursor_theme* theme, const(char)* name);
wl_buffer* wl_cursor_image_get_buffer(wl_cursor_image* image);
int wl_cursor_frame(wl_cursor* cursor, uint time);
int wl_cursor_frame_and_duration(wl_cursor* cursor, uint time, uint* duration);
