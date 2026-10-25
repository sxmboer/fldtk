/*
 * `extern(C)` bindings for the core of libwayland-client: the whole
 * public API of `wayland-client-core.h` and `wayland-util.h` (Wayland
 * 1.24). Not a port of an FLTK header -- infrastructure, the same role
 * `fl.xlib` plays for libX11. The protocol objects themselves (the
 * `wl_compositor`, `wl_surface`, ... request wrappers and listener
 * structs) are in the generated module `fl.wayland_protocol`.
 *
 * C names are kept, as in `fl.xlib`, so FLTK's Wayland driver code
 * reads the same in D. The `static inline` helpers of `wayland-util.h`
 * (`wl_fixed_*`) are D functions here; its `wl_container_of()` and
 * `wl_list_for_each()` macros are not bound.
 *
 * Only compiled into a build with Wayland support
 * (`version (FLDTK_HAVE_WAYLAND)`).
 */
module fl.wayland_client;

version (FLDTK_HAVE_WAYLAND):

import core.stdc.config : c_long;
import core.stdc.stdarg : va_list;

extern (C) nothrow @nogc:

// -- wayland-util.h -----------------------------------------------------

struct wl_object;

/// One request or event of an interface: its name, its argument
/// signature, and the interfaces of its object/new_id arguments.
struct wl_message
{
    const(char)* name;
    const(char)* signature;
    const(wl_interface*)* types;
}

/// A protocol interface: its name, version, requests (`methods`) and
/// events.
struct wl_interface
{
    const(char)* name;
    int version_;
    int method_count;
    const(wl_message)* methods;
    int event_count;
    const(wl_message)* events;
}

/// A doubly-linked list link, embedded in the elements of a list.
struct wl_list
{
    wl_list* prev;
    wl_list* next;
}

void wl_list_init(wl_list* list);
void wl_list_insert(wl_list* list, wl_list* elm);
void wl_list_remove(wl_list* elm);
int wl_list_length(const(wl_list)* list);
int wl_list_empty(const(wl_list)* list);
void wl_list_insert_list(wl_list* list, wl_list* other);

/// A dynamic array, as protocol `array` arguments arrive.
struct wl_array
{
    size_t size;
    size_t alloc;
    void* data;
}

void wl_array_init(wl_array* array);
void wl_array_release(wl_array* array);
void* wl_array_add(wl_array* array, size_t size);
int wl_array_copy(wl_array* array, wl_array* source);

/// 24.8 signed fixed-point number, the protocol's `fixed` type.
alias wl_fixed_t = int;

/// `wl_fixed_to_double()`.
double wl_fixed_to_double(wl_fixed_t f) pure @safe { return f / 256.0; }
/// `wl_fixed_from_double()`.
wl_fixed_t wl_fixed_from_double(double d) pure @safe { return cast(wl_fixed_t)(d * 256.0); }
/// `wl_fixed_to_int()`.
int wl_fixed_to_int(wl_fixed_t f) pure @safe { return f / 256; }
/// `wl_fixed_from_int()`.
wl_fixed_t wl_fixed_from_int(int i) pure @safe { return i * 256; }

/// One marshalled argument.
union wl_argument
{
    int i;
    uint u;
    wl_fixed_t f;
    const(char)* s;
    wl_object* o;
    uint n;
    wl_array* a;
    int h;
}

alias wl_dispatcher_func_t = int function(const(void)* user_data, void* target,
    uint opcode, const(wl_message)* msg, wl_argument* args);

alias wl_log_func_t = void function(const(char)* fmt, va_list args);

// -- wayland-client-core.h ----------------------------------------------

struct timespec;
struct wl_proxy;
struct wl_display;
struct wl_event_queue;

/// `wl_proxy_marshal_flags()` flag: destroy the proxy after marshalling.
enum uint WL_MARSHAL_FLAG_DESTROY = 1 << 0;

void wl_event_queue_destroy(wl_event_queue* queue);

wl_proxy* wl_proxy_marshal_flags(wl_proxy* proxy, uint opcode,
    const(wl_interface)* interface_, uint version_, uint flags, ...);
wl_proxy* wl_proxy_marshal_array_flags(wl_proxy* proxy, uint opcode,
    const(wl_interface)* interface_, uint version_, uint flags, wl_argument* args);
void wl_proxy_marshal(wl_proxy* p, uint opcode, ...);
void wl_proxy_marshal_array(wl_proxy* p, uint opcode, wl_argument* args);
wl_proxy* wl_proxy_create(wl_proxy* factory, const(wl_interface)* interface_);
void* wl_proxy_create_wrapper(void* proxy);
void wl_proxy_wrapper_destroy(void* proxy_wrapper);
wl_proxy* wl_proxy_marshal_constructor(wl_proxy* proxy, uint opcode,
    const(wl_interface)* interface_, ...);
wl_proxy* wl_proxy_marshal_constructor_versioned(wl_proxy* proxy, uint opcode,
    const(wl_interface)* interface_, uint version_, ...);
wl_proxy* wl_proxy_marshal_array_constructor(wl_proxy* proxy, uint opcode,
    wl_argument* args, const(wl_interface)* interface_);
wl_proxy* wl_proxy_marshal_array_constructor_versioned(wl_proxy* proxy, uint opcode,
    wl_argument* args, const(wl_interface)* interface_, uint version_);
void wl_proxy_destroy(wl_proxy* proxy);
/// `implementation` points at a listener struct of function pointers.
int wl_proxy_add_listener(wl_proxy* proxy, void* implementation, void* data);
const(void)* wl_proxy_get_listener(wl_proxy* proxy);
int wl_proxy_add_dispatcher(wl_proxy* proxy, wl_dispatcher_func_t dispatcher_func,
    const(void)* dispatcher_data, void* data);
void wl_proxy_set_user_data(wl_proxy* proxy, void* user_data);
void* wl_proxy_get_user_data(wl_proxy* proxy);
uint wl_proxy_get_version(wl_proxy* proxy);
uint wl_proxy_get_id(wl_proxy* proxy);
void wl_proxy_set_tag(wl_proxy* proxy, const(char*)* tag);
const(char*)* wl_proxy_get_tag(wl_proxy* proxy);
const(char)* wl_proxy_get_class(wl_proxy* proxy);
const(wl_interface)* wl_proxy_get_interface(wl_proxy* proxy);
wl_display* wl_proxy_get_display(wl_proxy* proxy);
void wl_proxy_set_queue(wl_proxy* proxy, wl_event_queue* queue);
wl_event_queue* wl_proxy_get_queue(const(wl_proxy)* proxy);
const(char)* wl_event_queue_get_name(const(wl_event_queue)* queue);

wl_display* wl_display_connect(const(char)* name);
wl_display* wl_display_connect_to_fd(int fd);
void wl_display_disconnect(wl_display* display);
int wl_display_get_fd(wl_display* display);
int wl_display_dispatch(wl_display* display);
int wl_display_dispatch_queue(wl_display* display, wl_event_queue* queue);
int wl_display_dispatch_timeout(wl_display* display, const(timespec)* timeout);
int wl_display_dispatch_queue_timeout(wl_display* display, wl_event_queue* queue,
    const(timespec)* timeout);
int wl_display_dispatch_queue_pending(wl_display* display, wl_event_queue* queue);
int wl_display_dispatch_pending(wl_display* display);
int wl_display_get_error(wl_display* display);
uint wl_display_get_protocol_error(wl_display* display, const(wl_interface)** interface_, uint* id);
int wl_display_flush(wl_display* display);
int wl_display_roundtrip_queue(wl_display* display, wl_event_queue* queue);
int wl_display_roundtrip(wl_display* display);
wl_event_queue* wl_display_create_queue(wl_display* display);
wl_event_queue* wl_display_create_queue_with_name(wl_display* display, const(char)* name);
int wl_display_prepare_read_queue(wl_display* display, wl_event_queue* queue);
int wl_display_prepare_read(wl_display* display);
void wl_display_cancel_read(wl_display* display);
int wl_display_read_events(wl_display* display);
void wl_log_set_handler_client(wl_log_func_t handler);
void wl_display_set_max_buffer_size(wl_display* display, size_t max_buffer_size);
