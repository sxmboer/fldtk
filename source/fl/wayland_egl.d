/*
 * `extern(C)` bindings for libwayland-egl (`wayland-egl-core.h`), which
 * wraps a `wl_surface` into the native window EGL draws into on Wayland:
 * the whole public API (Wayland 1.24). Infrastructure, like
 * `fl.wayland_client`; used by `fl.wayland_gl_window_driver`.
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`); links against `libwayland-egl`.
 */
module fl.wayland_egl;

version (FLDTK_HAVE_WAYLAND):

import fl.wayland_protocol : wl_surface;

extern (C) nothrow @nogc:

struct wl_egl_window;

wl_egl_window* wl_egl_window_create(wl_surface* surface, int width, int height);
void wl_egl_window_destroy(wl_egl_window* egl_window);
void wl_egl_window_resize(wl_egl_window* egl_window, int width, int height, int dx, int dy);
void wl_egl_window_get_attached_size(wl_egl_window* egl_window, int* width, int* height);
