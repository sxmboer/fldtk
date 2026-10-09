/*
 * Ported from FL/Fl_Preferences.H + src/Fl_Preferences.cxx (FLTK 1.5.0). Stores user settings (window sizes, recent-file
 * lists, etc.) between application runs, in a human-legible (but
 * intentionally undocumented/non-API) text file under the user's config
 * directory. Preferences are organized as a tree of named groups, each
 * holding key/value entries; groups and entries can be enumerated,
 * created on demand, and deleted. `Root.userL`/`Root.systemL` pick a
 * per-user or system-wide file location; `Root.memory` (via the
 * `Preferences(null, group)` constructor) creates an in-RAM-only
 * database, never touching disk.
 *
 * Deviations from FLTK, all deliberate:
 *
 *  - **`Fl_Preferences::Node` is ported as `PreferencesNode`, not
 *    `Node`**. This is
 *    a real naming deviation from FLTK, not this project's usual
 *    faithful-by-default naming -- done specifically because `fl.
 *    preferences` is `public import`ed by `fl/package.d`, so a bare
 *    `Node` here collided with `fluid.node.Node` (Fluid's own,
 *    pervasively-used project-tree type) for any file doing a plain
 *    `import fl;` alongside `fluid.node`, forcing a selective-import
 *    workaround (`import fluid.node : Node;`) everywhere that
 *    combination came up. Renaming this side rather than `fluid.node.
 *    Node` was the deliberately smaller-blast-radius choice: this
 *    type's own name was referenced only within this file itself (51
 *    internal spots) versus `Node` being the single most pervasively
 *    used identifier across the entire `fluid/` tree. See
 *    `PORTING.md`'s `FL/Fl_Preferences.H` row.
 *
 *  - **Linux/Unix path resolution and UUID generation only.** FLTK
 *    dispatches through `Fl::system_driver()` (`Fl_Unix_System_Driver`/
 *    `Fl_WinAPI_System_Driver`/`Fl_Darwin_System_Driver`) for the
 *    per-platform preferences directory and UUID generation. This port
 *    has no driver abstraction at all yet (matching this project's
 *    established "concrete module, not an abstract-class hierarchy
 *    until a second platform actually needs one" approach -- see
 *    `fl.platform_x11`'s own row in `PORTING.md`), so only the Unix
 *    path-resolution logic (`preference_user_rootnode()`/
 *    `preference_system_rootnode()`/`preference_memory_rootnode()` in
 *    `Fl_Unix_System_Driver.cxx`) is ported, verbatim, as private
 *    functions in this module -- including the exact `$XDG_CONFIG_HOME`
 *    resolution, the legacy `~/.fltk/<vendor>` fallback-if-it-already-
 *    exists check, and `/etc/fltk/<vendor>/<application>.prefs` for
 *    `Root.system`. `newUUID()` uses Phobos' `std.uuid.randomUUID()`
 *    (a real RFC4122 random UUID generator) instead of transliterating
 *    FLTK's raw entropy-gathering fallback (time + rand() + a stack
 *    address + hostname, only used when `dlopen("libuuid")` fails) --
 *    a cleaner, stronger standard-library alternative, matching
 *    CONVENTIONS.md's "check for a cleaner D stdlib alternative before
 *    transliterating a raw C library call" convention.
 *  - **`Root`/file-access permission flags are `alias int`/`alias uint`
 *    plus manifest constants, not closed `enum`s** -- both are open
 *    bitmasks combined with `|`/tested with `&` throughout FLTK's
 *    own code (`root & CLEAR`, `root & CORE`, `flags | USER_WRITE_OK`),
 *    matching CONVENTIONS.md's established rule for this shape (same
 *    treatment as `Align`/`Color`/`Font`/`When`/`Damage`).
 *  - **`Fl_Preferences::PreferencesNode`'s internal child-list is a plain,
 *    chronologically-ordered `PreferencesNode[]` D array, not FLTK's
 *    prepend-to-head C linked list (`first_child_`/`next_`) plus a
 *    separately-maintained reversed lookup-index cache
 *    (`index_`/`createIndex()`/`updateIndex()`/`deleteIndex()`).**
 *    Traced through FLTK's own indexing math (both the slow
 *    linked-list-walk path and the `index_` cache path in
 *    `childNode()`, and the recursive write order in `Node::write()`)
 *    to confirm this is a faithful behavioral match, not just a
 *    convenient simplification: because FLTK *prepends* new
 *    children (newest at `first_child_`) but then *compensates* for
 *    that order in both `childNode(ix)` (walks `n-ix-1` steps into the
 *    newest-first list) and `write()` (recurses into `next_` -- the
 *    *older* sibling -- before writing itself), the net *observable*
 *    order in both cases is chronological (oldest first) -- exactly
 *    what a plain D array appended in insertion order already gives
 *    for free, with no reversal logic anywhere and no need for
 *    FLTK's `O(1)`-lookup index-cache optimization at all (D array
 *    indexing is already `O(1)`). Same treatment for `PreferencesNode`'s entries
 *    (`Entry[] entries_`, appended directly, replacing `entry_`'s
 *    manual `realloc()`-doubling growth).
 *  - **`Node::lastEntrySet` (FLTK: a single field *shared across
 *    every `PreferencesNode` instance* -- `int Fl_Preferences::Node::lastEntrySet`
 *    is a class-static, not per-object) is not ported as a field at
 *    all.** It exists purely as an implicit side-channel from
 *    `Node::set(name,value)` to `Node::add(line)`, used only during
 *    `RootNode::read()`'s strictly-sequential, single-pass file
 *    parsing (`add()`'s own doc comment: "only used in read operations
 *    when a single entry stretches over multiple lines") -- safe as a
 *    shared static there purely because parsing never interleaves two
 *    nodes' `set()`/`add()` calls. Ported instead as a local variable
 *    threaded directly through this module's `RootNode.read()` loop
 *    (`PreferencesNode.set()` returns the entry's index; a continuation line calls
 *    `PreferencesNode.appendToEntry(index, more)` directly) -- equivalent
 *    behavior, without a genuinely surprising piece of hidden global
 *    mutable state no other caller should ever touch.
 *  - **`Fl_Preferences::Name` (the `Name("File%d", i)` printf-style
 *    temporary-buffer helper class) is not ported at all.** It exists
 *    purely as a C++ RAII trick (`operator const char*` plus an
 *    auto-freed heap buffer) to let a formatted string be used inline
 *    as a `const char*` argument. Every entry/group name in this port
 *    is a plain D `string` parameter already, so callers needing a
 *    dynamic name just call `std.format.format("File%d", i)` directly
 *    -- no wrapper needed, same category of C++-only-trick substitution
 *    CONVENTIONS.md's Callback note documents elsewhere.
 *  - **No copy constructor or `operator=` override.** `Preferences` is
 *    a `class` (D reference type, matching every other widget port),
 *    so plain assignment (`auto b = a;`) already reproduces FLTK's
 *    copy-constructor semantics exactly -- both are a shallow copy of
 *    the `node`/`rootNode` reference pair, sharing the same underlying
 *    tree. Nothing to port; D's reference semantics already give this
 *    "for free" (same category of simplification as `FlGroup.clear()`'s
 *    virtual-dispatch note elsewhere in this port).
 *  - **`ID` is the real `PreferencesNode` class reference, not FLTK's
 *    `typedef void*`.** FLTK type-erases to `void*` purely so
 *    `Fl_Preferences.H` doesn't have to expose `PreferencesNode`'s full definition
 *    to every translation unit that only wants an opaque handle; D has
 *    no equivalent translation-unit-hiding concern (this whole library
 *    compiles as one unit), so `id()` returns a plain, type-safe `PreferencesNode`
 *    reference and `Preferences(ID id)`/`static bool remove(ID id)`
 *    take one directly -- no pointer casting anywhere.
 *  - **`Fl_Preferences(const char *path, const char *vendor, const char
 *    *application)` (the no-`flags` overload, marked
 *    `FL_DEPRECATED` FLTK since 1.4.0) is not ported.** Its only
 *    difference from the non-deprecated 4-argument overload is a
 *    missing `Root flags` parameter (equivalent to always passing
 *    `0`); trivially reconstructible by any caller
 *    (`new Preferences(path, vendor, application, 0)`), and D has no
 *    matching "deprecated but still compiles with a warning" 1:1
 *    mechanism worth adding purely to shadow one already-superseded
 *    overload.
 *  - **`Fl_Plugin`/`Fl_Plugin_Manager` (declared in the separate
 *    `FL/Fl_Plugin.H`, but implemented inside this same `.cxx` file
 *    FLTK) are out of scope for this port entirely** -- a distinct
 *    FLTK header/feature with its own `PORTING.md` row, not part
 *    of `Fl_Preferences.H`'s own public surface.
 *  - **No automatic flush-on-GC-collection can be relied on for
 *    timely disk writes.** FLTK's `~Fl_Preferences()` deletes the
 *    `RootNode` (which writes the file if dirty) the moment the *base*
 *    `Fl_Preferences` object's C++ stack/member lifetime ends --
 *    deterministic, immediate. D's GC provides no such deterministic
 *    timing: `~this()` for a GC-collected `Preferences`/`RootNode` may
 *    run during a later collection sweep, or (in a program that exits
 *    abruptly) not at all before the process ends. `~this()` is still
 *    ported, faithfully, as a best-effort fallback (guarded with
 *    `core.memory.GC.inFinalizer()`, matching CONVENTIONS.md's established
 *    GC-finalizer-hazard pattern, since walking the `PreferencesNode` tree to
 *    write it touches other GC-managed objects that may already be
 *    finalized) -- but callers that actually need the data saved
 *    **must call `.flush()` explicitly** (already real, public FLTK
 *    API) rather than rely on scope-exit/GC timing. Documented loudly
 *    here rather than silently inherited as an assumption, since
 *    silent data loss is a much worse failure mode than a dropped UI
 *    repaint.
 *  - **Locale-independent number formatting always, regardless of the
 *    `C_LOCALE` flag's value.** FLTK's non-`C_LOCALE` code path
 *    exists because C's `printf`/`scanf`/`atof` family respect
 *    `setlocale()` (a German locale writes `3,1415`, breaking portable
 *    file interchange) -- `Fl::system_driver()->clocale_vsnprintf()`/
 *    `clocale_vsscanf()` exist specifically to force the "C" locale for
 *    the `C_LOCALE`-flagged path. D's `std.format`/`std.conv` never
 *    consult the process locale at all (confirmed empirically this
 *    session), so this port's number formatting is already always
 *    locale-independent -- there is no legacy locale-dependent
 *    codepath to port. The `C_LOCALE` flag itself is still a real,
 *    faithfully-ported bit (for file-format/API-surface fidelity), it
 *    simply has no observable effect on this port's own formatting
 *    either way.
 */
module fl.preferences;

import std.string;
import std.conv : to, parse, ConvException;
import std.file : exists, mkdirRecurse, FileException;
import std.stdio : File;
import std.process : environment;
import std.uuid : randomUUID;
import std.format : format;

// ---------------------------------------------------------------------
// Root / file_access: open bitmasks (CONVENTIONS.md's alias+constants rule)
// ---------------------------------------------------------------------

alias Root = int;
enum Root rootUnknown = -1;
enum Root rootSystem = 0;
enum Root rootUser = 1;
enum Root rootMemory = 2;
enum Root rootMask = 0x00FF;
enum Root rootCore = 0x0100;
enum Root rootCLocale = 0x1000;
enum Root rootClear = 0x2000;
enum Root rootSystemL = rootSystem | rootCLocale;
enum Root rootUserL = rootUser | rootCLocale;
enum Root rootCoreSystemL = rootCore | rootSystemL;
enum Root rootCoreUserL = rootCore | rootUserL;
/// Deprecated FLTK ("Use CORE_SYSTEM_L instead") -- kept for parity.
enum Root rootCoreSystem = rootCore | rootSystem;
/// Deprecated FLTK ("Use CORE_USER_L instead") -- kept for parity.
enum Root rootCoreUser = rootCore | rootUser;

alias FileAccess = uint;
enum FileAccess faNone = 0x0000;
enum FileAccess faUserReadOk = 0x0001;
enum FileAccess faUserWriteOk = 0x0002;
enum FileAccess faUserOk = faUserReadOk | faUserWriteOk;
enum FileAccess faSystemReadOk = 0x0004;
enum FileAccess faSystemWriteOk = 0x0008;
enum FileAccess faSystemOk = faSystemReadOk | faSystemWriteOk;
enum FileAccess faAppOk = faSystemOk | faUserOk;
enum FileAccess faCoreReadOk = 0x0010;
enum FileAccess faCoreWriteOk = 0x0020;
enum FileAccess faCoreOk = faCoreReadOk | faCoreWriteOk;
enum FileAccess faAllReadOk = faUserReadOk | faSystemReadOk | faCoreReadOk;
enum FileAccess faAllWriteOk = faUserWriteOk | faSystemWriteOk | faCoreWriteOk;
enum FileAccess faAll = faAllReadOk | faAllWriteOk;

/// A single key/value pair. Ported from `Fl_Preferences::Entry`.
private struct Entry
{
    string name;
    string value;
}

// ---------------------------------------------------------------------
// Lenient, locale-independent numeric parsing (matching C's atoi()/
// atof() leniency -- garbage input yields 0, never an exception; see
// this module's own top comment on why D's formatting/parsing needs no
// C_LOCALE-style special-casing).
// ---------------------------------------------------------------------

private int cAtoi(string s)
{
    size_t i = 0;
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) i++;
    size_t start = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    size_t digitsStart = i;
    while (i < s.length && s[i] >= '0' && s[i] <= '9') i++;
    if (i == digitsStart) return 0;
    try
        return to!int(s[start .. i]);
    catch (ConvException)
        return 0;
}

private double cAtof(string s)
{
    size_t i = 0;
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) i++;
    string rest = s[i .. $];
    try
        return parse!double(rest);
    catch (Exception)
        return 0.0;
}

// ---------------------------------------------------------------------
// Text/hex encoding, ported from decodeText()/set(key,text)'s inline
// escaper/decodeHex()/set(key,data,size)'s inline hex writer.
// ---------------------------------------------------------------------

private string encodeText(string text)
{
    bool needsEscape = false;
    foreach (c; text)
        if (c < 32 || c == '\\' || c == 0x7f) { needsEscape = true; break; }
    if (!needsEscape) return text;

    auto buf = appender!string;
    foreach (c; text)
    {
        if (c == '\\') buf.put("\\\\");
        else if (c == '\n') buf.put("\\n");
        else if (c == '\r') buf.put("\\r");
        else if (c < 32 || c == 0x7f)
        {
            buf.put('\\');
            buf.put(cast(char)('0' + ((c >> 6) & 3)));
            buf.put(cast(char)('0' + ((c >> 3) & 7)));
            buf.put(cast(char)('0' + (c & 7)));
        }
        else
            buf.put(c);
    }
    return buf.data;
}

private string decodeText(string src)
{
    auto buf = appender!string;
    size_t i = 0;
    while (i < src.length)
    {
        char c = src[i];
        if (c == '\\' && i + 1 < src.length)
        {
            char n = src[i + 1];
            if (n == '\\') { buf.put('\\'); i += 2; }
            else if (n == 'n') { buf.put('\n'); i += 2; }
            else if (n == 'r') { buf.put('\r'); i += 2; }
            else if (n >= '0' && n <= '9' && i + 3 < src.length)
            {
                char v = cast(char)(((src[i + 1] - '0') << 6) + ((src[i + 2] - '0') << 3) + (src[i + 3] - '0'));
                buf.put(v);
                i += 4;
            }
            else i++; // error, matching FLTK's silent skip
        }
        else { buf.put(c); i++; }
    }
    return buf.data;
}

private string encodeHex(const(ubyte)[] data)
{
    static immutable char[16] lu = "0123456789abcdef";
    auto buf = appender!string;
    foreach (b; data)
    {
        buf.put(lu[b >> 4]);
        buf.put(lu[b & 0xf]);
    }
    return buf.data;
}

private ubyte[] decodeHex(string src)
{
    int hexVal(char c)
    {
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return c - '0';
    }

    size_t size = src.length / 2;
    auto data = new ubyte[size];
    foreach (i; 0 .. size)
        data[i] = cast(ubyte)((hexVal(src[2 * i]) << 4) | hexVal(src[2 * i + 1]));
    return data;
}

import std.array : appender;

// ---------------------------------------------------------------------
// PreferencesNode: a group's key/value entries plus its child groups.
// ---------------------------------------------------------------------

/// A single node (group) in a preferences tree: its own key/value
/// entries, plus its child groups. Also serves as `Preferences.ID`
/// (see this module's top comment for why that's the real class here,
/// not FLTK's type-erased `void*`). Ported from
/// `Fl_Preferences::PreferencesNode`.
final class PreferencesNode
{
    private PreferencesNode parent_;
    private PreferencesNode[] children_;
    private RootNode rootNode_;
    private bool top_;
    private string path_;
    private Entry[] entries_;
    private bool dirty_;

    private this(string path)
    {
        path_ = path;
    }

    /// The last path segment (e.g. "Bed" for path "./Bed").
    string name() const
    {
        auto i = path_.lastIndexOf('/');
        return i < 0 ? path_ : path_[i + 1 .. $];
    }

    /// The full dotted/slashed path from the root (e.g. "./Bed/Alarm").
    string path() const { return path_; }

    PreferencesNode parent() { return top_ ? null : parent_; }

    private void setParent(PreferencesNode pn)
    {
        parent_ = pn;
        pn.children_ ~= this;
        path_ = pn.path_ ~ "/" ~ path_;
    }

    private void setRoot(RootNode r)
    {
        rootNode_ = r;
        top_ = true;
    }

    RootNode findRoot()
    {
        PreferencesNode n = this;
        while (n !is null)
        {
            if (n.top_) return n.rootNode_;
            n = n.parent_;
        }
        return null;
    }

    /// Finds (or creates, and every group along the way) the node at
    /// `path`, which must start with this node's own `path()`. Ported
    /// from `Node::find()`.
    PreferencesNode find(string path)
    {
        if (!path.startsWith(path_)) return null;
        auto rest = path[path_.length .. $];
        if (rest.length == 0) return this;
        if (rest[0] != '/') return null;

        foreach (child; children_)
        {
            auto nn = child.find(path);
            if (nn !is null) return nn;
        }

        auto s = rest[1 .. $];
        auto e = s.indexOf('/');
        auto segment = e < 0 ? s : s[0 .. e];
        auto nd = new PreferencesNode(segment);
        nd.setParent(this);
        dirty_ = true;
        return nd.find(path);
    }

    /// Finds (creating if necessary) the child at the relative `path`
    /// (which may itself contain `/`s). Ported from `Node::addChild()`.
    PreferencesNode addChild(string path)
    {
        return find(path_ ~ "/" ~ path);
    }

    /// Finds a node relative to this one without creating anything
    /// missing. `"."` is this node, `"./"` is the root, a leading
    /// `"./"` makes the rest relative to the root. Ported from
    /// `Node::search()`. `offset==0` is FLTK's own "caller didn't
    /// pass one" sentinel -- safe to reuse verbatim here too, since a
    /// resolved offset is always `>= 2` (`path_.length + 1`, and every
    /// node's own `path_` is at least `"."`, length 1).
    PreferencesNode search(string path)
    {
        return searchImpl(path, 0);
    }

    private PreferencesNode searchImpl(string path, ptrdiff_t offset)
    {
        if (offset == 0)
        {
            if (path.length > 0 && path[0] == '.')
            {
                if (path.length == 1) return this;
                if (path[1] == '/')
                {
                    PreferencesNode root = this;
                    while (root.parent() !is null) root = root.parent_;
                    if (path.length == 2) return root;
                    return root.searchImpl(path[2 .. $], 2);
                }
            }
            offset = cast(ptrdiff_t) path_.length + 1;
        }
        auto pathLen = cast(ptrdiff_t) path_.length;
        if (pathLen < offset - 1) return null;
        auto len = pathLen - offset;
        if (len <= 0 || (cast(ptrdiff_t) path.length >= len && path[0 .. len] == path_[offset .. $]))
        {
            if (len > 0 && cast(ptrdiff_t) path.length == len)
                return this;
            if (len <= 0 || (cast(ptrdiff_t) path.length > len && path[len] == '/'))
            {
                foreach (child; children_)
                {
                    auto nn = child.searchImpl(path, offset);
                    if (nn !is null) return nn;
                }
                return null;
            }
        }
        return null;
    }

    int nChildren() const { return cast(int) children_.length; }

    /// Ordered chronologically (oldest first) -- see this module's top
    /// comment for why this matches FLTK's own observable order
    /// despite FLTK's internal linked list being newest-first.
    PreferencesNode childNode(int ix)
    {
        if (ix < 0 || ix >= children_.length) return null;
        return children_[ix];
    }

    string child(int ix)
    {
        auto nd = childNode(ix);
        return nd is null ? null : nd.name();
    }

    /// Removes this node (and everything below it) from its parent.
    /// Returns false if this was already unparented (e.g. the root).
    bool remove()
    {
        auto p = parent();
        if (p is null) return false;
        auto idx = -1;
        foreach (i, c; p.children_)
            if (c is this) { idx = cast(int) i; break; }
        if (idx < 0) return false;
        p.children_ = p.children_[0 .. idx] ~ p.children_[idx + 1 .. $];
        p.dirty_ = true;
        return true;
    }

    void deleteAllChildren()
    {
        children_ = null;
        dirty_ = true;
    }

    int nEntry() const { return cast(int) entries_.length; }
    Entry entry(int i) const { return entries_[i]; }

    /// Creates or updates an entry, returning its index (used by
    /// `RootNode.read()`'s multi-line continuation handling -- see this
    /// module's top comment on why that's a local variable here rather
    /// than FLTK's shared-static `lastEntrySet`).
    int set(string name, string value)
    {
        foreach (i, ref e; entries_)
        {
            if (e.name == name)
            {
                if (e.value != value)
                {
                    e.value = value;
                    dirty_ = true;
                }
                return cast(int) i;
            }
        }
        entries_ ~= Entry(name, value);
        dirty_ = true;
        return cast(int) entries_.length - 1;
    }

    /// Appends more text to an already-set entry's value (a multi-line
    /// value continuation while reading a file). Ported from
    /// `Node::add()`, but taking an explicit index instead of reading
    /// the old shared-static `lastEntrySet`.
    void appendToEntry(int index, string more)
    {
        if (index < 0 || index >= entries_.length) return;
        entries_[index].value ~= more;
    }

    /// Returns null if no such entry exists.
    string get(string name) const
    {
        auto i = getEntry(name);
        return i >= 0 ? entries_[i].value : null;
    }

    int getEntry(string name) const
    {
        foreach (i, e; entries_)
            if (e.name == name) return cast(int) i;
        return -1;
    }

    bool deleteEntry(string name)
    {
        auto i = getEntry(name);
        if (i < 0) return false;
        entries_ = entries_[0 .. i] ~ entries_[i + 1 .. $];
        dirty_ = true;
        return true;
    }

    void deleteAllEntries()
    {
        entries_ = null;
        dirty_ = true;
    }

    /// Recursively: is this node, any of its children, or any of its
    /// once-recursively-dirty descendants dirty?
    bool dirty() const
    {
        if (dirty_) return true;
        foreach (c; children_)
            if (c.dirty()) return true;
        return false;
    }

    void clearDirtyFlags()
    {
        dirty_ = false;
        foreach (c; children_) c.clearDirtyFlags();
    }

    /// Writes this node's own group header + entries, then recurses
    /// into children -- chronological order (see this module's top
    /// comment). Ported from `Node::write()`.
    void write(File f)
    {
        f.writef("\n[%s]\n\n", path_);
        foreach (e; entries_)
        {
            if (e.value is null)
            {
                f.writef("%s\n", e.name);
                continue;
            }
            f.writef("%s:", e.name);
            auto src = e.value;
            auto first = src.length < 60 ? src.length : 60;
            f.writef("%s\n", src[0 .. first]);
            src = src[first .. $];
            while (src.length > 0)
            {
                auto chunkLen = src.length < 80 ? src.length : 80;
                f.writef("+%s\n", src[0 .. chunkLen]);
                src = src[chunkLen .. $];
            }
        }
        dirty_ = false;
        foreach (c; children_) c.write(f);
    }
}

// ---------------------------------------------------------------------
// RootNode: file path resolution and disk I/O for one database.
// ---------------------------------------------------------------------

/// Manages file paths and reading/writing for one preferences database.
/// Ported from `Fl_Preferences::RootNode`.
final class RootNode
{
    private Preferences prefs_;
    private string filename_;
    private string vendor_;
    private string application_;
    private Root rootType_;

    /// `Root.userL`/`Root.systemL`-style constructor.
    this(Preferences prefs, Root root, string vendor, string application)
    {
        prefs_ = prefs;
        rootType_ = root & ~rootClear;
        filename_ = preferenceRootnode(root, vendor, application);
        vendor_ = vendor.length ? vendor : "unknown";
        application_ = application.length ? application : "unknown";
        if ((root & rootClear) == 0) read();
    }

    /// Explicit-path constructor.
    this(Preferences prefs, string path, string vendor, string application, Root flags)
    {
        prefs_ = prefs;
        rootType_ = rootUser | (flags & rootCLocale);
        if (vendor.length == 0) vendor = "unknown";
        if (application.length == 0)
        {
            application = "unknown";
            filename_ = path;
        }
        else
        {
            filename_ = "%s/%s.prefs".format(path, application);
        }
        vendor_ = vendor;
        application_ = application;
        if ((flags & rootClear) == 0) read();
    }

    /// In-RAM-only ("runtime"/memory) database.
    this(Preferences prefs)
    {
        prefs_ = prefs;
        rootType_ = rootMemory;
    }

    string filename() const { return filename_; }
    Root root() const { return rootType_; }

    int read()
    {
        if ((rootType_ & rootMask) == rootMemory)
        {
            prefs_.node.clearDirtyFlags();
            return 0;
        }
        if (filename_.length == 0) return -1;
        if ((rootType_ & rootCore) != 0 && (fileAccess_ & faCoreReadOk) == 0)
        {
            prefs_.node.clearDirtyFlags();
            return -1;
        }
        if ((rootType_ & rootMask) == rootUser && (fileAccess_ & faUserReadOk) == 0)
        {
            prefs_.node.clearDirtyFlags();
            return -1;
        }
        if ((rootType_ & rootMask) == rootSystem && (fileAccess_ & faSystemReadOk) == 0)
        {
            prefs_.node.clearDirtyFlags();
            return -1;
        }
        if (!exists(filename_)) return -1;

        File f;
        try
            f = File(filename_, "rb");
        catch (Exception)
            return -1;
        scope (exit) f.close();

        // The first 3 lines are always the fixed header comments ("; FLTK
        // preferences file format 1.0" / "; vendor: ..." / "; application:
        // ..."); no special-casing is needed to skip them, since every
        // '('/'#')-led line (including these three) is already treated as
        // a no-op comment by setLine() below, matching FLTK's own
        // Node::set(const char*) exactly.
        PreferencesNode nd = prefs_.node;
        foreach (rawLine; f.byLine())
        {
            string line = rawLine.idup;
            if (line.length > 0 && line[0] == '[')
            {
                auto end = line.indexOf(']');
                auto groupPath = end < 0 ? line[1 .. $] : line[1 .. end];
                nd = prefs_.node.find(groupPath);
            }
            else if (line.length > 0 && line[0] == '+')
            {
                if (nd !is null && line.length > 1)
                    nd.appendToEntry(nd.nEntry() - 1, line[1 .. $]);
            }
            else if (line.length > 0)
            {
                if (nd !is null) setLine(nd, line);
            }
        }
        prefs_.node.clearDirtyFlags();
        return 0;
    }

    /// Parses one "key:value" (or ";comment") line from the file,
    /// matching `Node::set(const char *line)`.
    private void setLine(PreferencesNode nd, string line)
    {
        if (line[0] == ';' || line[0] == '#') return; // comment, not stored
        auto c = line.indexOf(':');
        if (c >= 0) nd.set(line[0 .. c], line[c + 1 .. $]);
        else nd.set(line, "");
    }

    int write()
    {
        if ((rootType_ & rootMask) == rootMemory)
        {
            prefs_.node.clearDirtyFlags();
            return 0;
        }
        if (filename_.length == 0) return -1;
        if ((rootType_ & rootCore) != 0 && (fileAccess_ & faCoreWriteOk) == 0) return -1;
        if ((rootType_ & rootMask) == rootUser && (fileAccess_ & faUserWriteOk) == 0) return -1;
        if ((rootType_ & rootMask) == rootSystem && (fileAccess_ & faSystemWriteOk) == 0) return -1;

        if (!makePathForFile(filename_)) return -1;
        File f;
        try
            f = File(filename_, "wb");
        catch (Exception)
            return -1;
        f.writef("; FLTK preferences file format 1.0\n");
        f.writef("; vendor: %s\n", vendor_);
        f.writef("; application: %s\n", application_);
        prefs_.node.write(f);
        f.close();

        protectPath(filename_);
        return 0;
    }

    /// Creates (and returns) a directory next to the preferences file
    /// suitable for storing extra application data. Ported from
    /// `RootNode::getPath()`.
    bool getPath(out string path)
    {
        if (filename_.length == 0) { path = ""; return true; } // runtime prefs

        auto p = filename_.replace("\\", "/");
        auto slash = p.lastIndexOf('/');
        auto name = slash < 0 ? p : p[slash + 1 .. $];
        auto dot = p.lastIndexOf('.');
        auto nameStart = slash < 0 ? 0 : slash + 1;

        if (dot < 0 || dot < nameStart)
            p ~= (name.length == 0 ? "data" : ".data");
        else
            p = p[0 .. dot];

        bool ok = makePath(p);
        if (preferencesNeedProtectionCheck && p.startsWith("/etc/fltk/"))
            protectDir(p);
        path = p ~ "/";
        return ok;
    }
}

// ---------------------------------------------------------------------
// Unix path resolution, ported from Fl_Unix_System_Driver.cxx.
// ---------------------------------------------------------------------

private enum preferencesNeedProtectionCheck = true; // Unix: RootNode::write()/getPath() chmod the /etc/fltk/ tree user-readable

private string preferenceRootnode(Root root, string vendor, string application)
{
    if (vendor.length == 0) vendor = "unknown";
    if (application.length == 0) application = "unknown";
    switch (root & rootMask)
    {
    case rootUser:
        version (Windows)
            return preferenceWindowsRootnode(root, vendor, application);
        else
            return preferenceUserRootnode(vendor, application);
    case rootSystem:
        version (Windows)
            return preferenceWindowsRootnode(root, vendor, application);
        else
            return "/etc/fltk/%s/%s.prefs".format(vendor, application);
    case rootMemory:
    default:
        return "";
    }
}

// ---------------------------------------------------------------------
// Windows path resolution, ported from
// Fl_WinAPI_System_Driver::preference_rootnode().
// ---------------------------------------------------------------------

version (Windows)
{
    import core.sys.windows.windows : MAX_PATH;
    import core.sys.windows.winerror : S_OK;
    import core.sys.windows.shlobj : SHGetFolderPathW, CSIDL_APPDATA,
        CSIDL_COMMON_APPDATA, SHGFP_TYPE;
    import core.stdc.wchar_ : wcslen;
    import std.utf : toUTF8;

    /// `%APPDATA%\<vendor>\<application>.prefs` for `Root.user`, or the
    /// "common application data" folder (`%ALLUSERSPROFILE%`-ish) for
    /// `Root.system` -- both resolved via `SHGetFolderPathW()`
    /// (`CSIDL_APPDATA`/`CSIDL_COMMON_APPDATA`) exactly like FLTK,
    /// rather than reading `%APPDATA%` as a plain environment variable:
    /// FLTK's own comment notes this gives the "current, potentially
    /// redirected" path (roaming profiles, folder-redirection policies)
    /// a raw env-var read wouldn't reliably reflect. Every backslash in
    /// the result is converted to a forward slash afterward, matching
    /// both FLTK's own final normalization loop and this module's
    /// `/`-joined-path convention everywhere else (see
    /// `preferencesFilename()`'s own `.replace()`).
    private string preferenceWindowsRootnode(Root root, string vendor, string application)
    {
        int csidl = (root & rootMask) == rootSystem ? CSIDL_COMMON_APPDATA : CSIDL_APPDATA;
        wchar[MAX_PATH] buf;
        auto res = SHGetFolderPathW(null, csidl, null, SHGFP_TYPE.SHGFP_TYPE_CURRENT, buf.ptr);
        if (res != S_OK) return ""; // matches FLTK: don't guess at a fallback, just skip persistence

        auto dir = toUTF8(buf[0 .. wcslen(buf.ptr)]);
        return "%s/%s/%s.prefs".format(dir, vendor, application).replace("\\", "/");
    }
}

private string homeDirectory()
{
    auto home = environment.get("HOME", "");
    if (home.length > 0) return home;
    version (Posix)
    {
        import core.sys.posix.pwd : getpwuid;
        import core.sys.posix.unistd : getuid;

        auto pw = getpwuid(getuid());
        if (pw !is null && pw.pw_dir !is null)
            return pw.pw_dir.fromStringz.idup;
    }
    return "";
}

/// Ported from `Fl_Unix_System_Driver::preference_user_rootnode()`:
/// `$XDG_CONFIG_HOME/<vendor>/<application>.prefs` (defaulting
/// `$XDG_CONFIG_HOME` to `$HOME/.config`), falling back to the legacy
/// `$HOME/.fltk/<vendor>/<application>.prefs` location only if that
/// legacy vendor directory already exists on disk.
private string preferenceUserRootnode(string vendor, string application)
{
    auto home = homeDirectory();

    auto xdg = environment.get("XDG_CONFIG_HOME", "");
    string base;
    if (xdg.length == 0)
        base = home ~ "/.config";
    else
    {
        base = xdg;
        if (base.length > 0 && base[$ - 1] != '/') base ~= "/";
        if (base.startsWith("~/")) base = home ~ base[1 .. $];
        base = base.replace("${HOME}", home).replace("$HOME/", home ~ "/");
    }
    if (base.length == 0 || base[$ - 1] != '/') base ~= "/";
    base ~= vendor;

    if (!exists(base))
    {
        auto legacy = home ~ "/.fltk/" ~ vendor;
        if (exists(legacy))
            return legacy ~ "/" ~ application ~ ".prefs";
    }

    return base ~ "/" ~ application ~ ".prefs";
}

private bool makePath(string dir)
{
    if (dir.length == 0) return false;
    if (exists(dir)) return true;
    try
    {
        mkdirRecurse(dir);
        return true;
    }
    catch (FileException)
        return false;
}

private bool makePathForFile(string filename)
{
    auto slash = filename.lastIndexOf('/');
    if (slash <= 0) return true;
    return makePath(filename[0 .. slash]);
}

private void protectDir(string dir)
{
    version (Posix)
    {
        import core.sys.posix.sys.stat : chmod;

        chmod(dir.toStringz(), octal!755);
    }
}

private void protectPath(string filename)
{
    version (Posix)
    {
        import core.sys.posix.sys.stat : chmod;

        if (!filename.startsWith("/etc/fltk/")) return;
        // chmod every directory component down to (not including) the
        // file itself user-readable, matching RootNode::write()'s own
        // loop exactly: filename[9] is the '/' right after "/etc/fltk".
        size_t p = 9;
        while (true)
        {
            chmod(filename[0 .. p].toStringz(), octal!755);
            auto next = filename.indexOf('/', p + 1);
            if (next < 0) break;
            p = next;
        }
        chmod(filename.toStringz(), octal!644);
    }
}

private import std.conv : octal;

private FileAccess fileAccess_ = faAll;

/// A UUID as generated by the system, e.g.
/// `"937C4900-51AA-4C11-8DD3-7AB59944F03E"` -- see this module's top
/// comment for why this uses `std.uuid.randomUUID()` rather than
/// transliterating FLTK's raw entropy fallback.
string newUUID()
{
    return randomUUID().toString().toUpper();
}

/// Tell the preferences system which files in the file system it may
/// read, create, or write. See the `fa*` constants above. Ported from
/// `Fl_Preferences::file_access()`.
FileAccess fileAccess() { return fileAccess_; }
/// ditto
void fileAccess(FileAccess flags) { fileAccess_ = flags; }

/// Determines the file name and path that would be used for the given
/// parameters, without touching the file system. Ported from the
/// static `Fl_Preferences::filename()`.
Root preferencesFilename(out string path, Root root, string vendor, string application)
{
    auto fn = preferenceRootnode(root, vendor, application);
    path = fn.replace("\\", "/");
    return fn.length ? root : rootUnknown;
}

// ---------------------------------------------------------------------
// Preferences: the public handle onto one group (node) of a database.
// ---------------------------------------------------------------------

/// Stores user settings between application runs. See this module's
/// top comment. Ported from `Fl_Preferences`.
class Preferences
{
    package(fl) PreferencesNode node;
    package(fl) RootNode rootNode;

    private static Preferences runtimePrefs_;

    /// Opens (creating if necessary) the base/root database for
    /// `vendor`/`application`, e.g.
    /// `new Preferences(rootUserL, "fltk.org", "myapp")`.
    this(Root root, string vendor, string application)
    {
        node = new PreferencesNode(".");
        rootNode = new RootNode(this, root, vendor, application);
        node.setRoot(rootNode);
        if (root & rootClear) clear();
    }

    /// Opens (creating if necessary) a database at an arbitrary
    /// location: `"$path/$application.prefs"`, or `path` taken
    /// literally if `application` is empty.
    this(string path, string vendor, string application, Root flags)
    {
        node = new PreferencesNode(".");
        rootNode = new RootNode(this, path, vendor, application, flags);
        node.setRoot(rootNode);
        if (flags & rootClear) clear();
    }

    /// Opens (creating if necessary) the child group `group` (may
    /// contain `/`s) within `parent`'s database.
    this(Preferences parent, string group)
    {
        if (parent is null) parent = runtimePrefs();
        rootNode = parent.rootNode;
        node = parent.node.addChild(group);
    }

    /// Opens the `groupIndex`'th child group of `parent` (chronological
    /// order, oldest first -- see `PreferencesNode.childNode()`'s doc comment). An
    /// out-of-range index creates a new group named with a fresh UUID.
    this(Preferences parent, int groupIndex)
    {
        rootNode = parent.rootNode;
        if (groupIndex < 0 || groupIndex >= parent.groups())
            node = parent.node.addChild(newUUID());
        else
            node = parent.node.childNode(groupIndex);
    }

    /// Reopens a previously-retrieved `id()` handle.
    this(PreferencesNode id)
    {
        node = id;
        rootNode = id.findRoot();
    }

    ~this()
    {
        import core.memory : GC;

        if (GC.inFinalizer()) return; // see this module's top comment
        if (node !is null && node.parent() is null && rootNode !is null)
            rootNode.write();
    }

    private static Preferences runtimePrefs()
    {
        if (runtimePrefs_ is null)
        {
            runtimePrefs_ = new Preferences();
            runtimePrefs_.node = new PreferencesNode(".");
            runtimePrefs_.rootNode = new RootNode(runtimePrefs_);
            runtimePrefs_.node.setRoot(runtimePrefs_.rootNode);
        }
        return runtimePrefs_;
    }

    private this() { }

    /// An opaque-ish handle that can later be reused with
    /// `new Preferences(id)`/`Preferences.remove(id)`, as long as the
    /// database stays open (see this module's top comment: unlike
    /// FLTK, this is the real `PreferencesNode`, not a `void*`).
    PreferencesNode id() const { return cast(PreferencesNode) node; }

    /// Removes the group referred to by `id_` from its database.
    static bool remove(PreferencesNode id_) { return id_.remove(); }

    /// This entry's own name (the last path segment).
    string name() const { return node.name(); }
    /// The full path to this entry from the database root.
    string path() const { return node.path(); }

    int groups() { return node.nChildren(); }
    string group(int numGroup) { return node.child(numGroup); }
    bool groupExists(string key) { return node.search(key) !is null; }
    bool deleteGroup(string group)
    {
        auto nd = node.search(group);
        return nd !is null && nd.remove();
    }
    bool deleteAllGroups() { node.deleteAllChildren(); return true; }

    int entries() { return node.nEntry(); }
    string entry(int index) { return node.entry(index).name; }
    bool entryExists(string key) { return node.getEntry(key) >= 0; }
    bool deleteEntry(string key) { return node.deleteEntry(key); }
    bool deleteAllEntries() { node.deleteAllEntries(); return true; }

    bool clear()
    {
        auto r1 = deleteAllGroups();
        auto r2 = deleteAllEntries();
        return r1 && r2;
    }

    // -- int --

    bool get(string key, out int value, int defaultValue)
    {
        auto v = node.get(key);
        value = v is null ? defaultValue : cAtoi(v);
        return v !is null;
    }

    bool set(string key, int value)
    {
        node.set(key, to!string(value));
        return true;
    }

    // -- float --

    bool get(string key, out float value, float defaultValue)
    {
        auto v = node.get(key);
        value = v is null ? defaultValue : cast(float) cAtof(v);
        return v !is null;
    }

    bool set(string key, float value)
    {
        node.set(key, "%g".format(value));
        return true;
    }

    bool set(string key, float value, int precision)
    {
        node.set(key, "%.*g".format(precision, value));
        return true;
    }

    // -- double --

    bool get(string key, out double value, double defaultValue)
    {
        auto v = node.get(key);
        value = v is null ? defaultValue : cAtof(v);
        return v !is null;
    }

    bool set(string key, double value)
    {
        node.set(key, "%g".format(value));
        return true;
    }

    bool set(string key, double value, int precision)
    {
        node.set(key, "%.*g".format(precision, value));
        return true;
    }

    // -- string --

    /// `maxSize`-truncated read into a fixed buffer, matching
    /// FLTK's `get(key, char*, default, maxSize)` overload.
    bool get(string key, out string value, string defaultValue, int maxSize)
    {
        auto v = node.get(key);
        if (v !is null)
        {
            auto decoded = v.indexOf('\\') >= 0 ? decodeText(v) : v;
            value = decoded.length > maxSize ? decoded[0 .. maxSize] : decoded;
            return true;
        }
        value = defaultValue.length > maxSize ? defaultValue[0 .. maxSize] : defaultValue;
        return false;
    }

    bool get(string key, out string value, string defaultValue)
    {
        auto v = node.get(key);
        if (v !is null)
        {
            value = v.indexOf('\\') >= 0 ? decodeText(v) : v;
            return true;
        }
        value = defaultValue;
        return false;
    }

    bool set(string key, string value)
    {
        node.set(key, encodeText(value));
        return true;
    }

    // -- binary data --

    /// `maxSize`-capped read into a fixed buffer.
    bool get(string key, ubyte[] data, const(ubyte)[] defaultValue, out int size)
    {
        auto maxSize = cast(int) data.length;
        auto v = node.get(key);
        if (v !is null)
        {
            auto decoded = decodeHex(v);
            auto n = decoded.length > maxSize ? maxSize : cast(int) decoded.length;
            data[0 .. n] = decoded[0 .. n];
            size = n;
            return true;
        }
        auto n = defaultValue.length > maxSize ? maxSize : cast(int) defaultValue.length;
        if (n > 0) data[0 .. n] = defaultValue[0 .. n];
        size = n;
        return false;
    }

    /// Allocates and returns a freshly-sized array (FLTK's `char
    /// *&`/`void *&` out-allocating overload).
    bool get(string key, out ubyte[] data, const(ubyte)[] defaultValue)
    {
        auto v = node.get(key);
        if (v !is null)
        {
            data = decodeHex(v);
            return true;
        }
        data = defaultValue.dup;
        return false;
    }

    bool set(string key, const(ubyte)[] data)
    {
        node.set(key, encodeHex(data));
        return true;
    }

    /// The length, in bytes, of the raw stored value for `key` (before
    /// any hex/escape decoding) -- 0 if the entry doesn't exist.
    int size(string key)
    {
        auto v = node.get(key);
        return v is null ? 0 : cast(int) v.length;
    }

    /// Returns the actual file path (and `Root`) this database is
    /// backed by -- ported from the non-static `Fl_Preferences::
    /// filename(char*, size_t)` member overload, distinct from the
    /// static `Fl_Preferences::filename()`/this module's own
    /// `preferencesFilename()` free function (which only *predicts* a
    /// path without opening anything, e.g. before this `Preferences` is
    /// even constructed). Forwards to `rootNode`. Needed by
    /// `source/test/preferences.fl`'s `readPrefs()` to re-query the
    /// just-opened app's own resolved path/root (matching FLTK's own
    /// `app.filename(path, FL_PATH_MAX)` call).
    Root filename(out string path) const
    {
        if (rootNode is null) return rootUnknown;
        path = rootNode.filename();
        return rootNode.root();
    }

    /// Fills `path` with a directory suitable for extra application
    /// data, creating it if necessary. Returns false if it could not
    /// be created.
    bool getUserdataPath(out string path)
    {
        return rootNode !is null && rootNode.getPath(path);
    }

    /// Writes the database to disk if it (or anything below it) has
    /// unsaved changes. Returns -1 on error, 0 if written, 1 if there
    /// was nothing to write.
    int flush()
    {
        auto d = dirty();
        if (d != 1) return d;
        return rootNode.write();
    }

    /// 1 if `flush()`/the destructor would write to disk, 0 if
    /// unchanged, -1 on an internal error.
    int dirty()
    {
        PreferencesNode n = node;
        while (n !is null && n.parent() !is null) n = n.parent();
        return n is null ? -1 : (n.dirty() ? 1 : 0);
    }
}

unittest
{
    // encodeText()/decodeText() round-tripping, including the
    // backslash/newline/carriage-return special cases and the octal
    // fallback for other control characters.
    void checkText(string s)
    {
        assert(decodeText(encodeText(s)) == s);
    }

    checkText("plain ascii");
    checkText("back\\slash");
    checkText("new\nline");
    checkText("carriage\rreturn");
    checkText("bell\x07and\x01control");
    checkText("");
    assert(encodeText("plain ascii") == "plain ascii"); // no escaping needed -> identity
}

unittest
{
    // encodeHex()/decodeHex() round-tripping.
    ubyte[] data = [0x00, 0x01, 0xff, 0x7f, 0xab, 0xcd];
    auto hex = encodeHex(data);
    assert(hex == "0001ff7fabcd");
    assert(decodeHex(hex) == data);
}

unittest
{
    // cAtoi()/cAtof(): C atoi()/atof()-style leniency -- garbage input
    // yields 0/0.0 rather than throwing, matching FLTK's use of
    // atoi()/atof() (which never fail) instead of D's throwing
    // std.conv.to()/parse().
    assert(cAtoi("42") == 42);
    assert(cAtoi("-17") == -17);
    assert(cAtoi("  8") == 8);
    assert(cAtoi("garbage") == 0);
    assert(cAtoi("") == 0);
    assert(cAtoi("12abc") == 12);

    import std.math : isClose;

    assert(isClose(cAtof("3.5"), 3.5));
    assert(isClose(cAtof("-2.25"), -2.25));
    assert(cAtof("garbage") == 0.0);
    assert(cAtof("") == 0.0);
}

unittest
{
    // PreferencesNode tree: addChild()/find() create-on-demand, search() lookup-
    // only, childNode() chronological ordering, remove().
    auto root = new PreferencesNode(".");

    auto a = root.addChild("A");
    auto b = root.addChild("B");
    assert(a !is null && b !is null);
    assert(root.nChildren() == 2);
    // Chronological (oldest first), not FLTK's internal newest-
    // first linked-list order -- see this module's top comment.
    assert(root.childNode(0) is a);
    assert(root.childNode(1) is b);
    assert(root.child(0) == "A");
    assert(root.child(1) == "B");

    // find() creates intermediate groups on demand, one call.
    auto deep = root.addChild("A/nested/deep");
    assert(deep !is null);
    assert(deep.path() == "./A/nested/deep");
    assert(deep.name() == "deep");
    assert(a.nChildren() == 1); // "nested" was created under A, not root

    // search() never creates anything.
    assert(root.search("./A/nested/deep") is deep);
    assert(root.search("./A/nested/missing") is null);
    assert(root.search(".") is root);
    assert(root.search("./") is root);
    assert(a.search(".") is a);
    assert(a.search("./") is root);

    // remove() detaches from the parent.
    assert(b.remove());
    assert(root.nChildren() == 1);
    assert(root.search("./B") is null);
}

unittest
{
    // PreferencesNode entries: set()/get()/getEntry()/deleteEntry(), dirty
    // tracking.
    auto nd = new PreferencesNode(".");
    assert(!nd.dirty());

    auto idx = nd.set("key1", "value1");
    assert(idx == 0);
    assert(nd.dirty());
    assert(nd.get("key1") == "value1");
    assert(nd.getEntry("key1") == 0);
    assert(nd.get("missing") is null);

    nd.clearDirtyFlags();
    assert(!nd.dirty());
    nd.set("key1", "value1"); // unchanged -> stays clean
    assert(!nd.dirty());
    nd.set("key1", "value2"); // changed -> dirty again
    assert(nd.dirty());
    assert(nd.get("key1") == "value2");

    nd.appendToEntry(idx, "-more");
    assert(nd.get("key1") == "value2-more");

    assert(nd.deleteEntry("key1"));
    assert(!nd.deleteEntry("key1")); // already gone
    assert(nd.get("key1") is null);
}

unittest
{
    // Preferences over an in-RAM-only ("runtime"/memory) database:
    // get/set for every value type, groups/entries enumeration,
    // deletion, dirty()/flush() never touching disk.
    auto p = new Preferences(null, "TestGroup");

    assert(p.set("intval", 42));
    int iv;
    assert(p.get("intval", iv, -1));
    assert(iv == 42);
    assert(!p.get("missing_int", iv, -1));
    assert(iv == -1);

    assert(p.set("floatval", 3.5f));
    float fv;
    assert(p.get("floatval", fv, -1.0f));
    import std.math : isClose;

    assert(isClose(fv, 3.5f));

    assert(p.set("doubleval", 2.71828, 4));
    double dv;
    assert(p.get("doubleval", dv, -1.0));
    assert(isClose(dv, 2.7183, 1e-3, 1e-3));

    assert(p.set("strval", "hello\nworld"));
    string sv;
    assert(p.get("strval", sv, "default"));
    assert(sv == "hello\nworld");
    assert(!p.get("missing_str", sv, "default"));
    assert(sv == "default");

    ubyte[] bin = [1, 2, 3, 250, 251];
    assert(p.set("binval", bin));
    ubyte[] readBuf = new ubyte[10];
    int readSize;
    assert(p.get("binval", readBuf, [], readSize));
    assert(readSize == 5);
    assert(readBuf[0 .. 5] == bin);

    assert(p.entries() == 5);
    assert(p.entryExists("intval"));
    assert(!p.entryExists("nope"));
    assert(p.deleteEntry("intval"));
    assert(p.entries() == 4);

    // Groups.
    auto child1 = new Preferences(p, "Child1");
    auto child2 = new Preferences(p, "Child2");
    assert(p.groups() == 2);
    assert(p.groupExists("Child1"));
    assert(p.deleteGroup("Child1"));
    assert(p.groups() == 1);
    assert(!p.groupExists("Child1"));

    // Memory-backed databases never touch disk.
    assert(p.dirty() == 1);
    assert(p.flush() == 0);
}

unittest
{
    // Full file read/write round-trip through a real temp directory
    // (Root.userL would touch the real user config dir -- the explicit
    // path/vendor/application/flags constructor instead points at an
    // isolated temp directory, matching fl.text_buffer's own real-file
    // test precedent).
    import std.file : tempDir, rmdirRecurse, exists, mkdirRecurse;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir(), "fldtk-prefs-test-" ~ randomUUID().toString());
    mkdirRecurse(dir);
    scope (exit) if (exists(dir)) rmdirRecurse(dir);

    {
        auto p = new Preferences(dir, "fldtk.test", "app", rootCLocale);
        p.set("width", 800);
        p.set("height", 600);
        auto win = new Preferences(p, "window");
        win.set("title", "Hello, World!");
        win.set("ratio", 1.5);
        ubyte[] icon = [0xde, 0xad, 0xbe, 0xef];
        win.set("icon", icon);
        assert(p.flush() == 0);
    }

    auto path = buildPath(dir, "app.prefs");
    assert(exists(path));

    {
        auto p2 = new Preferences(dir, "fldtk.test", "app", rootCLocale);
        int w, h;
        assert(p2.get("width", w, -1));
        assert(p2.get("height", h, -1));
        assert(w == 800 && h == 600);

        assert(p2.groupExists("window"));
        auto win2 = new Preferences(p2, "window");
        string title;
        assert(win2.get("title", title, ""));
        assert(title == "Hello, World!");
        double ratio;
        assert(win2.get("ratio", ratio, -1.0));
        import std.math : isClose;

        assert(isClose(ratio, 1.5));

        ubyte[] readBuf = new ubyte[10];
        int readSize;
        assert(win2.get("icon", readBuf, [], readSize));
        assert(readSize == 4);
        assert(readBuf[0 .. 4] == [0xde, 0xad, 0xbe, 0xef]);

        assert(p2.dirty() == 0); // freshly read, nothing changed yet
    }
}

unittest
{
    // `Preferences.filename()` reaches the public
    // `RootNode.filename()`/`.root()` -- see this method's own doc
    // comment.
    import std.file : tempDir, rmdirRecurse, exists, mkdirRecurse;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    auto dir = buildPath(tempDir(), "fldtk-prefs-test-" ~ randomUUID().toString());
    mkdirRecurse(dir);
    scope (exit) if (exists(dir)) rmdirRecurse(dir);

    auto p = new Preferences(dir, "fldtk.test", "app", rootCLocale);
    string path;
    auto root = p.filename(path);
    assert(root == (rootUser | rootCLocale));
    // Not buildPath(dir, "app.prefs") -- filename()/getPath() always
    // join with a literal '/' regardless of platform (see this module's
    // own base~"/"~application~".prefs" construction above), so on
    // Windows the result mixes `dir`'s native backslashes with a
    // forward-slash join, which buildPath()'s all-native-separator
    // result wouldn't match.
    assert(path == dir ~ "/app.prefs");

    auto mem = new Preferences(rootMemory, "fldtk.test", "memapp");
    string memPath;
    assert(mem.filename(memPath) == rootMemory);
}

unittest
{
    // newUUID(): a real 36-character RFC4122-shaped UUID (8-4-4-4-12
    // hex groups separated by dashes) -- see this module's top comment
    // for why this uses std.uuid.randomUUID() rather than FLTK's
    // raw entropy fallback.
    auto uuid = newUUID();
    assert(uuid.length == 36);
    assert(uuid[8] == '-' && uuid[13] == '-' && uuid[18] == '-' && uuid[23] == '-');
    assert(newUUID() != newUUID()); // vanishingly unlikely to collide
}

unittest
{
    // Root/FileAccess bit composition sanity.
    assert(rootSystemL == (rootSystem | rootCLocale));
    assert(rootUserL == (rootUser | rootCLocale));
    assert((rootCoreUserL & rootCore) != 0);
    assert((rootCoreUserL & rootMask) == rootUser);
    assert(faAll == (faAllReadOk | faAllWriteOk));
    assert((faUserOk & faUserReadOk) != 0 && (faUserOk & faUserWriteOk) != 0);
}
