/*
 * `extern(C)` bindings for the parts of GLib/GObject that Pango's API
 * exposes: the types Pango's declarations use (`GObject`, `GList`,
 * `GError`, ...), and the functions needed to release what Pango hands
 * back (`g_object_unref()`, `g_free()`, `g_list_free()`, ...).
 *
 * This is deliberately a subset, unlike `fl.cairo_c`/`fl.pango_c`, which
 * bind their libraries' whole public API: GLib and GObject are general
 * C utility and object-system libraries with thousands of functions,
 * none of which fldtk or a Pango user needs beyond these. Types Pango
 * only passes by pointer are opaque here (`GBytes`, `GData`, `GValue`,
 * `GParamSpec`, ...); types whose fields a Pango user reads or embeds
 * are spelled out (`GList`, `GSList`, `GError`, `GString`, `GQueue`,
 * and `GObject`/`GObjectClass`/`GTypeModule`, which Pango's public
 * instance and class structs embed by value).
 *
 * Transcribed from the GLib 2.88 headers (`/usr/include/glib-2.0/`), with
 * GtkD's `glib.c.types`/`gobject.c.types` as a cross-check for names
 * and layouts: struct fields are camelCase with aliases under the C
 * names, as in `fl.cairo_c`. GLib's scalar typedefs (`gint`, `gboolean`,
 * `gchar`, ...) are not declared; the bindings use the D types they
 * stand for (`int`, `int`, `char`, ...), so `gboolean` is `int`, never
 * `bool`, and `gunichar` is `dchar`.
 *
 * Only compiled into a Pango-enabled build (`version (FLDTK_HAVE_PANGO)`,
 * on by default on Linux, off with dub configuration `linux-no-cairo`; on Windows only with `windows-cairo`).
 */
module fl.glib_c;

version (FLDTK_HAVE_PANGO):

// Runs GLib's and GObject's GCC constructors on Windows; see fl.mingw_runtime.
version (Windows) import fl.mingw_runtime;

/// A numerical type identifier (`GType`, a `gsize`).
alias GType = size_t;

/// A string interned as a number (`GQuark`).
alias GQuark = uint;

/// Called to free a piece of data (`GDestroyNotify`).
alias GDestroyNotify = extern (C) void function(void* data);

struct GData;
struct GBytes;
struct GValue;
struct GParamSpec;
struct GObjectConstructParam;
struct GMarkupParseContext;

/// A doubly linked list node (`GList`).
struct GList
{
    void* data;
    GList* next;
    GList* prev;
}

/// A singly linked list node (`GSList`).
struct GSList
{
    void* data;
    GSList* next;
}

/// A double-ended queue (`GQueue`).
struct GQueue
{
    GList* head;
    GList* tail;
    uint length;
}

/// A growable string (`GString`).
struct GString
{
    char* str;
    size_t len;
    size_t allocatedLen;
    alias allocated_len = allocatedLen; // C name
}

/// An error reported by a GLib-style API (`GError`).
struct GError
{
    GQuark domain;
    int code;
    char* message;
}

/// The base of every type class structure (`GTypeClass`).
struct GTypeClass
{
    GType gType;
    alias g_type = gType; // C name
}

/// The base of every instance structure (`GTypeInstance`).
struct GTypeInstance
{
    GTypeClass* gClass;
    alias g_class = gClass; // C name
}

/// The base object type (`GObject`), embedded by value at the start of
/// every Pango object's instance struct.
struct GObject
{
    GTypeInstance gTypeInstance;
    uint refCount;
    GData* qdata;
    alias g_type_instance = gTypeInstance; // C name
    alias ref_count = refCount; // C name
}

/// The class structure of `GObject` (`GObjectClass`), embedded by value
/// at the start of every Pango class struct.
struct GObjectClass
{
    GTypeClass gTypeClass;
    GSList* constructProperties;
    extern (C) GObject* function(GType type, uint n_construct_properties, GObjectConstructParam* construct_properties) constructor;
    extern (C) void function(GObject* object, uint property_id, const(GValue)* value, GParamSpec* pspec) setProperty;
    extern (C) void function(GObject* object, uint property_id, GValue* value, GParamSpec* pspec) getProperty;
    extern (C) void function(GObject* object) dispose;
    extern (C) void function(GObject* object) finalize;
    extern (C) void function(GObject* object, uint n_pspecs, GParamSpec** pspecs) dispatchPropertiesChanged;
    extern (C) void function(GObject* object, GParamSpec* pspec) notify;
    extern (C) void function(GObject* object) constructed;
    size_t flags;
    size_t nConstructProperties;
    void* pspecs;
    size_t nPspecs;
    void*[3] pdummy;
    alias g_type_class = gTypeClass; // C name
    alias construct_properties = constructProperties; // C name
    alias set_property = setProperty; // C name
    alias get_property = getProperty; // C name
    alias dispatch_properties_changed = dispatchPropertiesChanged; // C name
    alias n_construct_properties = nConstructProperties; // C name
    alias n_pspecs = nPspecs; // C name
}

/// A loadable type module (`GTypeModule`), used by Pango's deprecated
/// engine API.
struct GTypeModule
{
    GObject parentInstance;
    uint useCount;
    GSList* typeInfos;
    GSList* interfaceInfos;
    char* name;
    alias parent_instance = parentInstance; // C name
    alias use_count = useCount; // C name
    alias type_infos = typeInfos; // C name
    alias interface_infos = interfaceInfos; // C name
}

extern (C) nothrow @nogc
{
    // ---- glib/gmem.h

    void g_free(void* mem);

    // ---- glib/glist.h, glib/gslist.h

    void g_list_free(GList* list);
    void g_list_free_full(GList* list, GDestroyNotify free_func);
    uint g_list_length(GList* list);
    void g_slist_free(GSList* list);
    void g_slist_free_full(GSList* list, GDestroyNotify free_func);
    uint g_slist_length(GSList* list);

    // ---- glib/gerror.h, glib/gquark.h

    void g_error_free(GError* error);
    const(char)* g_quark_to_string(GQuark quark);

    // ---- glib/gbytes.h

    GBytes* g_bytes_new(const(void)* data, size_t size);
    const(void)* g_bytes_get_data(GBytes* bytes, size_t* size);
    size_t g_bytes_get_size(GBytes* bytes);
    void g_bytes_unref(GBytes* bytes);

    // ---- gobject/gobject.h, gobject/gtype.h

    void* g_object_ref(void* object);
    void g_object_unref(void* object);
    const(char)* g_type_name(GType type);
}
