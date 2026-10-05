/*
 * The named, savable shell-command database -- ported from FLTK's
 * `Fd_Shell_Command`/`Fd_Shell_Command_List` (`fluid/app/
 * shell_command.h`/`.cxx`, the *other* half of that file from
 * `fluid.shell_process`, the runner -- see that module's own top
 * comment for the two-phase split). Every saved command has a name, a
 * `&Shell`-menu label/shortcut, a platform-or-user-or-host-or-env
 * *condition* controlling whether it even appears in the menu, the
 * command text itself, and save-flags (`fluid.shell_process.
 * ShellFlags`, reused directly, not redefined here).
 *
 * `ShellCondition`/`ToolStore` are real D `enum`s (closed,
 * non-combinable tag sets, matching CONVENTIONS.md's own porting
 * convention) -- FLTK's own plain `enum { ALWAYS, NEVER, ... }`/
 * `enum class Tool_Store`. `ToolStore` lives here rather than a shared
 * module since `ShellCommand` is its only real consumer in this port
 * so far (FLTK also uses it for `Layout_Suite`/`Layout_Preset`,
 * neither ported here -- move this enum out if that ever changes, no
 * need to build for the hypothetical now).
 *
 * `ShellCommand.run()` needs project-specific macro values
 * (`fluid.shell_process.ShellMacros`) it has no way to compute itself
 * (project state lives in `gui_main.d`) -- `macroProvider`, a module-
 * level delegate `gui_main.d` wires once at startup, mirrors
 * `fluid.shell_process`'s own outward-delegate shape for exactly this
 * reason.
 */
module fluid.shell_command;

import std.conv : to, ConvException;
import std.array : Appender;
import std.format : format;

import fl.preferences : Preferences;
import fl.enumerations : stateAlt;

import fluid.shell_process;
import fluid.project_reader : Reader;

/// Ported from FLTK's plain `enum { ALWAYS, NEVER, MAC_ONLY,
/// UX_ONLY, WIN_ONLY, MAC_AND_UX_ONLY, USER_ONLY, HOST_ONLY, ENV_ONLY }`
/// -- kept in this exact declaration order (its numeric value is
/// persisted directly, via `Fd_Shell_Command::condition`'s own `int`
/// storage, in both `.fl` project text and user preferences, so the
/// order here is a real, load-bearing wire format, not just a
/// declaration convenience).
enum ShellCondition
{
    always,
    never,
    macOnly,
    uxOnly,
    winOnly,
    macAndUxOnly,
    userOnly,
    hostOnly,
    envOnly,
}

/// Ported from FLTK's `enum class Tool_Store`. `internal`/`file`
/// are real FLTK values (a built-in default, and the transient
/// "this came from an `.flcmd` import" tag respectively) but never a
/// *persisted* `ShellCommand.storage` here -- only `user`/`project` are
/// ever written to disk, matching FLTK's own Settings-dialog Store
/// `Choice`, which likewise only ever offers those two.
enum ToolStore
{
    internal,
    user,
    project,
    file,
}

/// Computes this session's own `ShellMacros` on demand -- `gui_main.d`
/// wires this once at startup (it owns the actual project path/state;
/// this module has none), mirroring `fluid.shell_process`'s own
/// outward-delegate shape.
ShellMacros delegate() macroProvider;

/// Shows the "running a shell command" terminal window -- `gui_main.d`
/// wires this once at startup, same shape as `macroProvider` just
/// above. Kept as a delegate rather than a direct `import shell_run_
/// window : showShellRunWindow;` inside `run()` (a real, working
/// version of this that predates the delegate) specifically so this
/// module -- and everything that transitively imports it, including
/// `fluid.project_reader` for `ToolStore` -- has no compile-time
/// dependency on any `fluid/panels/*.fl`-generated file. A headless
/// `.fl -> .d` converter (no GUI at all) needs `project_reader.d`/
/// `code_writer.d` but never needs to actually show this window, so
/// leaving it unwired (`null`) there is correct, not a bug: `run()`
/// just skips showing the terminal in that case.
void delegate() showShellRunWindowHook;

/// One saved shell command -- ported from FLTK's `Fd_Shell_Command`
/// (prefix dropped, matching this project's established convention for
/// FLTK's own internal-namespace prefixes, e.g. `Menu_Manager_Node`
/// -> `MenuOwnerNode`, `Fl_Widget_Bin_Button` -> `BinButton`).
final class ShellCommand
{
    string name;
    string label;
    uint shortcut;
    ToolStore storage = ToolStore.user;
    ShellCondition condition = ShellCondition.always;
    string conditionData;
    string command;
    ShellFlags flags;

    this() { }

    /// Ported from FLTK's `Fd_Shell_Command(const std::string&)` --
    /// a fresh command seeded with sensible non-empty defaults (used by
    /// the Settings dialog's own "Add" button), not an empty shell a
    /// user would have to fill in every field of just to test.
    this(string inName)
    {
        name = inName;
        label = inName;
        condition = ShellCondition.always;
        command = `echo "Hello, FLUID!"`;
        flags = shellSaveProject | shellSaveSourceCode;
    }

    /// Ported from FLTK's `Fd_Shell_Command(const Fd_Shell_Command*)`
    /// -- a real field-for-field copy (the Settings dialog's own
    /// "Duplicate" button), not a reference share.
    this(ShellCommand rhs)
    {
        name = rhs.name;
        label = rhs.label;
        shortcut = rhs.shortcut;
        storage = rhs.storage;
        condition = rhs.condition;
        conditionData = rhs.conditionData;
        command = rhs.command;
        flags = rhs.flags;
    }

    /// Ported from FLTK's `is_active()` -- whether this command
    /// should appear in the live `&Shell` menu at all right now.
    /// Platform conditions are compile-time (`version()`), matching
    /// this port's own primary(Linux)/secondary(Windows) platform scope
    /// (see root `CONVENTIONS.md`) -- macOS is `false` throughout, this
    /// port's own explicitly out-of-scope-for-testing target.
    bool isActive() const
    {
        final switch (condition)
        {
        case ShellCondition.always: return true;
        case ShellCondition.never: return false;
        case ShellCondition.macOnly:
            version (OSX) return true; else return false;
        case ShellCondition.uxOnly:
            version (linux) return true; else return false;
        case ShellCondition.winOnly:
            version (Windows) return true; else return false;
        case ShellCondition.macAndUxOnly:
            version (OSX) return true;
            else version (linux) return true;
            else return false;
        case ShellCondition.userOnly:
        {
            string user = currentUserName();
            return user.length > 0 && user == conditionData;
        }
        case ShellCondition.hostOnly:
        {
            string host = currentHostName();
            return host.length > 0 && host == conditionData;
        }
        case ShellCondition.envOnly:
        {
            import std.process : environment;

            auto value = environment.get(conditionData);
            return value !is null && value.length > 0;
        }
        }
    }

    /// Ported from FLTK's `run()` plus the terminal-window-showing
    /// half of `run_shell_command()` that `fluid.shell_process`'s own
    /// `runShellCommand()` deliberately leaves to its caller (see that
    /// function's own doc comment on the layering -- only a saved
    /// `ShellCommand` knows its own `shellDontShowTerminal` flag).
    void run()
    {
        if (command.length == 0) return;

        if (!(flags & shellDontShowTerminal) && showShellRunWindowHook !is null)
            showShellRunWindowHook();

        auto macros = macroProvider !is null ? macroProvider() : ShellMacros.init;
        runShellCommand(command, flags, macros);
    }

    // -- Preferences persistence (ToolStore.user) --

    /// Ported from FLTK's `Fd_Shell_Command::read(Fl_Preferences&)`.
    void readFrom(Preferences prefs)
    {
        int tmp;
        prefs.get("name", name, "<unnamed>");
        prefs.get("label", label, "<no label>");
        prefs.get("shortcut", tmp, 0);
        shortcut = cast(uint) tmp;
        prefs.get("condition", tmp, cast(int) ShellCondition.always);
        condition = cast(ShellCondition) tmp;
        prefs.get("condition_data", conditionData, "");
        prefs.get("command", command, "");
        prefs.get("flags", tmp, 0);
        flags = tmp;
    }

    /// Ported from FLTK's `Fd_Shell_Command::write(Fl_Preferences&,
    /// bool)` -- `saveLocation` additionally persists `storage` itself,
    /// needed only for the standalone `.flcmd` export format (a user-
    /// prefs group's own location already implies `ToolStore.user`, an
    /// `.flcmd` file has no such implicit context).
    void writeTo(Preferences prefs, bool saveLocation = false)
    {
        prefs.set("name", name);
        prefs.set("label", label);
        if (shortcut != 0) prefs.set("shortcut", cast(int) shortcut);
        if (saveLocation) prefs.set("storage", cast(int) storage);
        if (condition != ShellCondition.always) prefs.set("condition", cast(int) condition);
        if (conditionData.length) prefs.set("condition_data", conditionData);
        if (command.length) prefs.set("command", command);
        if (flags != 0) prefs.set("flags", flags);
    }

    // -- `.fl` project-file persistence (ToolStore.project) --

    /// Ported from FLTK's `Fd_Shell_Command::read(Project_Reader*)`
    /// -- called with `r` positioned right after the "command" keyword
    /// token that introduced this block (matching FLTK's own
    /// caller/callee split, `Fd_Shell_Command_List::read()`/
    /// `Fd_Shell_Command::read()`).
    void readFrom(Reader r)
    {
        string open = r.readToken();
        if (open != "{") return;
        storage = ToolStore.project;
        while (true)
        {
            string tok = r.readToken();
            if (tok is null || tok == "}") break;
            switch (tok)
            {
            case "name": name = r.readValue(); break;
            case "label": label = r.readValue(); break;
            case "shortcut":
                try shortcut = to!uint(r.readValue());
                catch (ConvException) shortcut = 0;
                break;
            case "condition":
                try condition = cast(ShellCondition) to!int(r.readValue());
                catch (ConvException) condition = ShellCondition.always;
                break;
            case "condition_data": conditionData = r.readValue(); break;
            case "command": command = r.readValue(); break;
            case "flags":
                try flags = to!int(r.readValue());
                catch (ConvException) flags = 0;
                break;
            default: r.readValue(); break;
            }
        }
    }

    /// Ported from FLTK's `Fd_Shell_Command::write(Project_Writer*)`.
    /// `depth` is the indent level of the `command` keyword line, in
    /// `project_writer.d`'s own convention (2 spaces per level, GNU-style
    /// braces: the `{` sits one level deeper than the keyword, the
    /// properties one level deeper still, see that module's top comment).
    void writeTo(ref Appender!string buf, int depth)
    {
        string ind(int d) { string s; foreach (i; 0 .. d) s ~= "  "; return s; }

        buf ~= ind(depth) ~ "command\n";
        buf ~= ind(depth + 1) ~ "{\n";
        buf ~= ind(depth + 2) ~ "name {" ~ name ~ "}\n";
        buf ~= ind(depth + 2) ~ "label {" ~ label ~ "}\n";
        if (shortcut != 0) buf ~= ind(depth + 2) ~ format("shortcut %d\n", shortcut);
        if (condition != ShellCondition.always)
            buf ~= ind(depth + 2) ~ format("condition %d\n", cast(int) condition);
        if (conditionData.length) buf ~= ind(depth + 2) ~ "condition_data {" ~ conditionData ~ "}\n";
        if (command.length) buf ~= ind(depth + 2) ~ "command {" ~ command ~ "}\n";
        if (flags != 0) buf ~= ind(depth + 2) ~ format("flags %d\n", flags);
        buf ~= ind(depth + 1) ~ "}\n";
    }
}

/// Ported from FLTK's `get_current_user_name()` -- POSIX only
/// (`getpwuid_r()`, more reliable than `getlogin_r()`'s own
/// controlling-terminal requirement, matching FLTK's own choice on
/// non-Windows platforms); Windows returns `""` (this port's own
/// secondary platform target, not worth the `GetUserNameW()` investment
/// for a single condition-matching string).
string currentUserName()
{
    version (Posix)
    {
        import core.sys.posix.pwd : passwd, getpwuid_r;
        import core.sys.posix.unistd : geteuid;
        import std.string : fromStringz;

        passwd pwd_;
        passwd* result;
        char[16384] buf;
        if (getpwuid_r(geteuid(), &pwd_, buf.ptr, buf.length, &result) == 0 && result !is null)
            return fromStringz(pwd_.pw_name).idup;
        return "";
    }
    else
        return "";
}

/// Ported from FLTK's `get_current_host_name()` -- POSIX
/// `gethostname()`; Windows returns `""`, same reasoning as
/// `currentUserName()`.
string currentHostName()
{
    version (Posix)
    {
        import core.sys.posix.unistd : gethostname;
        import std.string : fromStringz;

        char[256] buf;
        if (gethostname(buf.ptr, buf.length) == 0)
            return fromStringz(buf.ptr).idup;
        return "";
    }
    else
        return "";
}

unittest
{
    auto always = new ShellCommand();
    always.condition = ShellCondition.always;
    assert(always.isActive());

    auto never = new ShellCommand();
    never.condition = ShellCondition.never;
    assert(!never.isActive());

    auto envSet = new ShellCommand();
    envSet.condition = ShellCondition.envOnly;
    envSet.conditionData = "FLDTK_SHELL_TEST_VAR_DOES_NOT_EXIST";
    assert(!envSet.isActive());
}

unittest
{
    import fluid.project_reader : Reader;

    auto cmd = new ShellCommand("My Command");
    cmd.shortcut = 'g';
    cmd.conditionData = "";
    cmd.command = "echo hi";

    auto buf = Appender!string();
    cmd.writeTo(buf, 0);

    // Re-parse the emitted "command { ... }" block the same way
    // `Reader.readShellCommands()` would -- confirms the writer's own
    // format is exactly what the reader expects, a real round trip,
    // not two independently-guessed shapes.
    auto r = new Reader(buf.data);
    string tok = r.readToken();
    assert(tok == "command");
    auto reread = new ShellCommand();
    reread.readFrom(r);

    assert(reread.name == "My Command");
    assert(reread.shortcut == 'g');
    assert(reread.command == "echo hi");
    assert(reread.storage == ToolStore.project);
}

/// Ported from FLTK's `Fd_Shell_Command_List` -- a plain, growable
/// list (`ShellCommand[]`, not FLTK's own hand-rolled `realloc()`-
/// grown C array -- D's own dynamic arrays already are that) holding
/// commands from *every* storage location at once (matching FLTK's
/// own single-list-multiple-storage-tags design, confirmed by
/// `Fd_Shell_Command_List::read(Project_Reader*)`'s own `clear(Tool_
/// Store::PROJECT)` call -- one list, filtered by `storage` per
/// operation, not two separate lists).
final class ShellCommandList
{
    ShellCommand[] list;

    void add(ShellCommand cmd) { list ~= cmd; }

    void insert(size_t index, ShellCommand cmd)
    {
        import std.array : insertInPlace;

        list.insertInPlace(index, cmd);
    }

    void remove(size_t index)
    {
        import std.algorithm.mutation : remove;

        list = list.remove(index);
    }

    void clear() { list = []; }

    /// Ported from FLTK's `clear(Tool_Store)` -- drops every entry
    /// with the given `storage`, keeping the rest (used before
    /// reloading a project's own `ToolStore.project` entries, so a
    /// second `&File/&Open` doesn't just keep appending).
    void clear(ToolStore storage)
    {
        import std.algorithm.iteration : filter;
        import std.array : array;

        list = list.filter!(c => c.storage != storage).array;
    }

    // -- Preferences persistence (ToolStore.user) --

    /// Ported from FLTK's `read(Fl_Preferences&, Tool_Store)`,
    /// including the one-time legacy-settings-migration branch (a
    /// pre-`ShellCommand`-list single "shell_command"/"shell_savefl"/
    /// etc. key set some very early version of real Fluid used) --
    /// ported faithfully since real user preference files from that
    /// era may still exist, not because this port ever wrote that shape
    /// itself.
    void readFromPrefs(Preferences prefs)
    {
        int ver;
        prefs.get("shell_commands_version", ver, 0);
        if (ver == 0)
        {
            string legacyCmd;
            int saveFl, saveCode, saveStrings_;
            prefs.get("shell_command", legacyCmd, `echo "Sample Shell Command"`);
            prefs.get("shell_savefl", saveFl, 1);
            prefs.get("shell_writecode", saveCode, 1);
            prefs.get("shell_writemsgs", saveStrings_, 0);

            auto cmd = new ShellCommand();
            cmd.storage = ToolStore.user;
            cmd.name = "Sample Shell Command";
            cmd.label = "Sample Shell Command";
            cmd.shortcut = stateAlt + 'g';
            cmd.command = legacyCmd;
            if (saveFl) cmd.flags |= shellSaveProject;
            if (saveCode) cmd.flags |= shellSaveSourceCode;
            if (saveStrings_) cmd.flags |= shellSaveStrings;
            add(cmd);
        }
        prefs.set("shell_commands_version", 1);

        auto group = new Preferences(prefs, "shell_commands");
        int n = group.groups();
        foreach (i; 0 .. n)
        {
            auto cmdPrefs = new Preferences(group, i);
            auto cmd = new ShellCommand();
            cmd.storage = ToolStore.user;
            cmd.readFrom(cmdPrefs);
            add(cmd);
        }
    }

    /// Ported from FLTK's `write(Fl_Preferences&, Tool_Store)` --
    /// only ever writes `ToolStore.user` entries (matching FLTK's
    /// own hardcoded filter; the parameter FLTK declares but never
    /// actually branches on).
    void writeToPrefs(Preferences prefs)
    {
        auto group = new Preferences(prefs, "shell_commands");
        group.deleteAllGroups();
        int index;
        foreach (cmd; list)
        {
            if (cmd.storage != ToolStore.user) continue;
            auto cmdPrefs = new Preferences(group, to!string(index++));
            cmd.writeTo(cmdPrefs);
        }
    }

    // -- `.fl` project-file persistence (ToolStore.project) --

    /// Ported from FLTK's `read(Project_Reader*)` -- `r` positioned
    /// right after the "shell_commands" Option keyword, matching
    /// `project_reader.d`'s own Options-loop call site.
    void readFromProject(Reader r)
    {
        string open = r.readToken();
        if (open != "{") return;
        clear(ToolStore.project);
        while (true)
        {
            string tok = r.readToken();
            if (tok is null || tok == "}") break;
            if (tok == "command")
            {
                auto cmd = new ShellCommand();
                add(cmd);
                cmd.readFrom(r);
            }
            else
                r.readValue(); // unknown -- skip its value defensively
        }
    }

    /// Ported from FLTK's `write(Project_Writer*)`.
    void writeToProject(ref Appender!string buf)
    {
        writeShellCommandsBlock(buf, list);
    }
}

/// The `shell_commands { ... }` block of a `.fl` project file: only
/// `ToolStore.project`-tagged entries, matching `readFromProject()`'s own
/// `clear(ToolStore.project)`-then-reload shape on the reading side (a
/// project reload never disturbs `ToolStore.user`/`.internal` entries,
/// which don't come from the `.fl` file at all). Writes nothing at all
/// when no entry qualifies. The single implementation behind both
/// `ShellCommandList.writeToProject()` and `ProjectWriter.generate()`.
void writeShellCommandsBlock(ref Appender!string buf, ShellCommand[] cmds)
{
    bool any;
    foreach (cmd; cmds)
        if (cmd.storage == ToolStore.project) { any = true; break; }
    if (!any) return;

    buf ~= "shell_commands\n  {\n";
    foreach (cmd; cmds)
        if (cmd.storage == ToolStore.project)
            cmd.writeTo(buf, 2);
    buf ~= "  }\n";
}

/// The single, shared `ShellCommandList` instance -- matches
/// `fluid.app_prefs.appPrefs`'s own precedent (one shared instance,
/// initialized once at startup, not one per caller) since both the
/// Settings dialog's own "Shell" tab (`settings_panel.fl`) and
/// `gui_main.d`'s `&Shell` menu-rebuilding need to see the *same* live
/// list, not independent copies. **Deliberately *not* a `static
/// this()`-initialized module global** the way `fluid.app_prefs.
/// appPrefs` itself is -- this module sits in a real, unavoidable
/// mutual-type-dependency cycle with `fluid.project_reader`
/// (`ShellCommand.readFrom(Reader)` needs `Reader`'s own type;
/// `Reader.shellCommands`/`readShellCommands()` need `ShellCommand`'s),
/// and that cycle already ran *through* `fluid.factory`'s own existing
/// `static this()` (its registry-population block) even before this
/// module existed. Adding a *second* `static this()` into the same
/// cycle left druntime with two module constructors it couldn't find a
/// valid relative order for -- a real, reproducible `Cyclic dependency
/// between module constructors` crash at program startup, not a
/// hypothetical one. `gui_main.d`'s `runEditor()` constructs this
/// explicitly instead (`shellCommandList = new ShellCommandList();`,
/// alongside its other one-time startup calls like `makeWidgetBin()`),
/// which needs no module-constructor ordering at all.
ShellCommandList shellCommandList;

unittest
{
    // GNU-style layout of the `shell_commands` block, byte-exact; only
    // `ToolStore.project` entries are written, and nothing at all when
    // none qualify.
    auto project = new ShellCommand("Proj Cmd");
    project.storage = ToolStore.project;
    project.command = "echo hi";
    auto user = new ShellCommand("User Cmd");
    user.storage = ToolStore.user;

    auto none = Appender!string();
    writeShellCommandsBlock(none, [user]);
    assert(none.data.length == 0);

    auto buf = Appender!string();
    writeShellCommandsBlock(buf, [user, project]);
    string expected = "shell_commands\n"
        ~ "  {\n"
        ~ "    command\n"
        ~ "      {\n"
        ~ "        name {Proj Cmd}\n"
        ~ "        label {Proj Cmd}\n"
        ~ "        command {echo hi}\n"
        ~ "        flags 3\n"
        ~ "      }\n"
        ~ "  }\n";
    assert(buf.data == expected, buf.data);
}
