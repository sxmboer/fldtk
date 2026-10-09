/*
 * Tokenizer + recursive tree builder for the `.fl` project-file
 * format. Ported from FLTK's `Fd_Project_Reader`/`Project_Reader`
 * (`fluid/io/Project_Reader.h`/`.cxx`), grounded directly in the real
 * grammar (`fluid/README_fl.txt`, plus real files like
 * `test/fast_slow.fl`/`test/valuators.fl`), not guessed:
 *
 * Every tree node is `TypeName instance_name { ...properties... }`,
 * optionally followed by a second `{ ...children... }` block if the
 * type can have children. Two reading *modes* matter:
 *
 *  - "token" mode (`readToken()`): used when scanning for the next
 *    Type name, property name, or a block boundary -- a bare `{`/`}`
 *    is returned AS a one-character punctuation string.
 *  - "value" mode (`readValue()`): used when a specific property's
 *    (or the instance name's) *value* is being fetched -- if the next
 *    char is `{`, the entire balanced/escaped brace span is consumed
 *    and its de-braced, unescaped content is returned as one string
 *    (this is how a multi-line callback body containing its own
 *    `{ }` pairs is embedded verbatim). Otherwise a plain unbraced
 *    word (e.g. `Double`, `47`) is read the same way as token mode.
 *
 * Escape handling inside a braced value (`read_quoted()` in FLTK):
 * `\n \t \r \a \b \f \v`, `\xHH` (hex, up to 2 digits), `\NNN` (octal,
 * up to 2 digits after the first), `\` followed directly by a newline
 * (line continuation, dropped), and any other `\X` as a literal `X`
 * (covers `\{`, `\}`, `\#`, `\\`). A `#` starts a comment (to end of
 * line) even *inside* braces unless escaped as `\#` -- this is why
 * `setup {\#include <stdio.h>}` needs the backslash.
 *
 * Not ported (genuinely unneeded for `test/fast_slow.fl`, deferred to
 * a later `.fl` file if one needs them): `.fd`/fdesign legacy format
 * and most Option keywords beyond `version`/`header_name`/
 * `code_name` -- **except** `use_FL_COMMAND`/`mergeback` (see `Reader.settings`) and
 * `i18n_type`/
 * `i18n_include`/`i18n_conditional`/`i18n_gnu_function`/
 * `i18n_gnu_static_function`/`i18n_pos_file`/`i18n_pos_set`, which
 * *are* interpreted for real (see `Reader.i18n`/`readProject()`'s own Options loop) -- every other
 * Option keyword in `optionKeywords` below is still just consumed
 * opaquely.
 *
 * `parent_properties` is fully parsed for real (see `parseNode()`'s
 * own `"parent_properties"` case), with a matching write-side mirror in
 * `project_writer.d`, backing `GridNode`'s real cell-placement
 * mechanism (`grid_node.d`'s own `cellOf`/`GridCellInfo`).
 */
module fluid.project_reader;

import std.conv : to, ConvException;

import fluid.node;
import fluid.factory;
import fluid.i18n : I18nSettings, I18nType;
import fluid.project_settings : ProjectSettings;
import fluid.layout_suite : LayoutSuite, LayoutPreset;
import fluid.shell_command : ShellCommand, ToolStore;

class Reader
{
    private string text;
    private size_t pos;

    /// Project-wide internationalization settings, parsed from the
    /// leading Options list (`i18n_type`/`i18n_include`/etc, see
    /// `readProject()`'s own Options loop) -- ported from FLTK's
    /// `fluid::proj::I18n::read()`. Defaults to `I18nSettings.init`
    /// (`I18nType.none`) for any `.fl` file that never sets `i18n_type`
    /// at all, matching FLTK's own `I18n::reset()` defaults.
    I18nSettings i18n;

    /// This project's own `ToolStore.project`-tagged shell commands
    /// (`fluid.shell_command`'s own "the other half of shell_command.h"
    /// port), parsed from the leading `shell_commands { command {...}
    /// ... }` Option block -- ported from FLTK's `Fd_Shell_Command_
    /// List::read(Project_Reader*)`/`Fd_Shell_Command::read(Project_
    /// Reader*)`. Empty for any `.fl` file with no `shell_commands`
    /// block at all, matching `i18n`'s own "absent means default" shape
    /// just above.
    ShellCommand[] shellCommands;

    /// This project's own `ToolStore.project`-tagged layout suites,
    /// parsed from the leading `snap { ver 1  current_suite {...}
    /// current_preset N  suite {...} ... }` Option block -- ported from
    /// FLTK's `Layout_List::read(Project_Reader*)`. `hasSnap` tells
    /// the caller (`gui_main.d`'s `loadProject()`) whether the file had
    /// a `snap` block at all, since `layoutCurrentSuite`/`
    /// layoutCurrentPreset` default to "suite 0, preset 0" either way
    /// and can't distinguish "the file explicitly selected the FLTK
    /// suite's Application preset" from "the file has no opinion."
    LayoutSuite[] layoutSuites;
    string layoutCurrentSuite;
    int layoutCurrentPreset;
    bool hasSnap;

    /// FLTK: `Project::code_file_name` (`code_name {...}` in the
    /// leading Options list) -- the Settings dialog's Project-tab "Code
    /// File:" override for the generated `.d` file's own name/path,
    /// independent of the `.fl` project file's own basename. Empty for
    /// any `.fl` file that never sets `code_name` at all (this port's
    /// own default, matching `gui_main.d`'s `writeCodeFile()`'s
    /// pre-existing "always the project's own basename" behavior).
    /// Unlike FLTK, `header_name` is read but discarded (still
    /// listed in `optionKeywords` purely so a `.fl` file FLTK wrote
    /// -- or an earlier fldtk session, before this field existed --
    /// still parses without error): this port generates one `.d` file
    /// per project with no header/source split for a header filename
    /// to configure at all.
    string codeFileName;

    /// `Settings -> Project`'s "dub single-file-package header" checkbox
    /// state (`settings_panel.fl`'s `dubHeaderButton`) -- see
    /// `project_writer.d`'s `generate()` `dubHeader` parameter for the
    /// write side and `code_writer.d`'s own `Writer.generate()`
    /// `dubHeader` parameter for what it actually controls. `false` for
    /// any `.fl` file that never sets `dub_header` at all.
    bool dubHeader;

    /// Code-generation flags from the leading Options block
    /// (`use_FL_COMMAND`, `mergeback`), see `fluid.project_settings`. Default-
    /// initialized for any `.fl` file that sets none of them.
    ProjectSettings settings;

    /// Every leading-Options keyword the file actually contained. The
    /// fields above hold defaults for anything absent, so a caller
    /// merging this file into an open project (`File/Insert`) uses this
    /// to apply only what the file set, as FLTK's reader does.
    bool[string] optionsSeen;

    this(string source)
    {
        text = source;
        pos = 0;
    }

    // -- raw character source, normalizing away '\r' entirely --

    private int peekRawChar()
    {
        size_t p = pos;
        while (p < text.length && text[p] == '\r')
            p++;
        return p < text.length ? cast(ubyte) text[p] : -1;
    }

    private int nextRawChar()
    {
        while (pos < text.length && text[pos] == '\r')
            pos++;
        if (pos >= text.length)
            return -1;
        return cast(ubyte) text[pos++];
    }

    private void skipWsAndComments()
    {
        while (true)
        {
            int c = peekRawChar();
            if (c == -1)
                return;
            if (c == ' ' || c == '\t' || c == '\n')
            {
                nextRawChar();
                continue;
            }
            if (c == '#')
            {
                while (true)
                {
                    int cc = peekRawChar();
                    if (cc == -1 || cc == '\n')
                        break;
                    nextRawChar();
                }
                continue;
            }
            break;
        }
    }

    private static bool isDelim(int c)
    {
        return c == -1 || c == ' ' || c == '\t' || c == '\n' || c == '{' || c == '}' || c == '#';
    }

    private string readSimpleWord()
    {
        auto start = pos;
        while (!isDelim(peekRawChar()))
            nextRawChar();
        return text[start .. pos];
    }

    private void appendEscape(ref char[] buf)
    {
        int c = nextRawChar();
        switch (c)
        {
        case 'n': buf ~= '\n'; break;
        case 't': buf ~= '\t'; break;
        case 'r': buf ~= '\r'; break;
        case 'a': buf ~= '\a'; break;
        case 'b': buf ~= '\b'; break;
        case 'f': buf ~= '\f'; break;
        case 'v': buf ~= '\v'; break;
        case '\n': break; // line continuation -- dropped
        case 'x':
        {
            int val = 0;
            int n = 0;
            while (n < 2 && isHex(peekRawChar()))
            {
                val = val * 16 + hexVal(nextRawChar());
                n++;
            }
            buf ~= cast(char) val;
            break;
        }
        default:
            if (c >= '0' && c <= '7')
            {
                int val = c - '0';
                int n = 1;
                while (n < 3 && isOct(peekRawChar()))
                {
                    val = val * 8 + (nextRawChar() - '0');
                    n++;
                }
                buf ~= cast(char) val;
            }
            else if (c != -1)
            {
                buf ~= cast(char) c;
            }
            break;
        }
    }

    private static bool isHex(int c)
    {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    private static int hexVal(int c)
    {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        return c - 'A' + 10;
    }

    private static bool isOct(int c)
    {
        return c >= '0' && c <= '7';
    }

    private string readBracedContent()
    {
        // Assumes the opening '{' has already been consumed.
        char[] buf;
        int depth = 1;
        while (true)
        {
            int c = nextRawChar();
            if (c == -1)
                break; // unterminated -- be forgiving
            if (c == '\\')
            {
                appendEscape(buf);
                continue;
            }
            if (c == '#')
            {
                while (true)
                {
                    int cc = peekRawChar();
                    if (cc == -1 || cc == '\n')
                        break;
                    nextRawChar();
                }
                continue;
            }
            if (c == '{')
            {
                depth++;
                buf ~= '{';
                continue;
            }
            if (c == '}')
            {
                depth--;
                if (depth == 0)
                    break;
                buf ~= '}';
                continue;
            }
            buf ~= cast(char) c;
        }
        return cast(string) buf;
    }

    /// Structural/token mode -- see this module's own doc comment.
    /// Returns `null` at EOF.
    string readToken()
    {
        skipWsAndComments();
        int c = peekRawChar();
        if (c == -1)
            return null;
        if (c == '{' || c == '}')
        {
            nextRawChar();
            return c == '{' ? "{" : "}";
        }
        return readSimpleWord();
    }

    /// Value mode -- see this module's own doc comment.
    string readValue()
    {
        skipWsAndComments();
        int c = peekRawChar();
        if (c == -1)
            return "";
        if (c == '{')
        {
            nextRawChar();
            return readBracedContent();
        }
        return readSimpleWord();
    }

    // -- tree building --

    private static immutable string[] optionKeywords = [
        "version", "header_name", "code_name", "include_guard", "gridx", "gridy",
        "i18n_type", "i18n_include", "i18n_conditional", "i18n_gnu_function",
        "i18n_gnu_static_function", "i18n_pos_file", "i18n_pos_set",
        "snap", "shell_commands", "mergeback", "dub_header",
        // Bare flags: no value follows, handled explicitly in
        // `readProject()`'s switch (the `default:` case would swallow
        // the next token).
        "use_FL_COMMAND", "do_not_include_H_from_C", "utf8_in_src",
        "avoid_early_includes",
    ];

    private static bool isOptionKeyword(string w)
    {
        foreach (k; optionKeywords)
            if (k == w)
                return true;
        return false;
    }

    /// Top-level entry point: parses the whole file into a forest of
    /// root nodes (in practice, almost always exactly one `Function`
    /// node). Ported from `Project_Reader::read_project()`.
    Node[] readProject()
    {
        i18n = I18nSettings.init;
        shellCommands = [];
        codeFileName = "";
        dubHeader = false;
        settings = ProjectSettings.init;
        layoutSuites = [];
        layoutCurrentSuite = "";
        layoutCurrentPreset = 0;
        hasSnap = false;
        optionsSeen = null;

        // Leading Options: flat `key [value]` pairs, in any order,
        // ending the moment a word isn't a known Option keyword.
        while (true)
        {
            auto saved = pos;
            string word = readToken();
            if (word is null)
                return [];
            if (!isOptionKeyword(word))
            {
                pos = saved;
                break;
            }
            optionsSeen[word] = true;
            // `i18n_type`/`i18n_include`/`shell_commands`/`snap`/etc are
            // interpreted for real (ported from `fluid::proj::I18n::
            // read()`, `Fd_Shell_Command_List::read()`, `Layout_List::
            // read()` respectively) -- `code_name` too, just below.
            // `header_name`/`include_guard`/`gridx`/`gridy` (no D
            // equivalent) fall through to the `default:` case and get
            // consumed opaquely, unparsed.
            switch (word)
            {
            case "i18n_type":
                try i18n.type = cast(I18nType) to!int(readValue());
                catch (ConvException) i18n.type = I18nType.none;
                break;
            case "i18n_gnu_function":
                i18n.gnuFunction = readValue();
                break;
            case "i18n_gnu_static_function":
                i18n.gnuStaticFunction = readValue();
                break;
            case "i18n_pos_file":
                i18n.posixFile = readValue();
                break;
            case "i18n_pos_set":
                i18n.posixSet = readValue();
                break;
            case "i18n_include":
                // Type-dependent, matching FLTK's own `I18n::
                // read()` exactly -- routes to whichever of gnu_include/
                // posix_include the *already-parsed* `i18n_type` value
                // selects (FLTK's own `write()` always emits
                // `i18n_type` first, before either `i18n_include`/
                // `i18n_conditional`, so this ordering assumption holds
                // for any file this port's own writer produced).
                if (i18n.type == I18nType.gnu)
                    i18n.gnuInclude = readValue();
                else if (i18n.type == I18nType.posix)
                    i18n.posixInclude = readValue();
                else
                    readValue();
                break;
            case "i18n_conditional":
                if (i18n.type == I18nType.gnu)
                    i18n.gnuConditional = readValue();
                else if (i18n.type == I18nType.posix)
                    i18n.posixConditional = readValue();
                else
                    readValue();
                break;
            case "shell_commands":
                readShellCommands();
                break;
            case "snap":
                readSnap();
                break;
            case "code_name":
                codeFileName = readValue();
                break;
            case "dub_header":
                try dubHeader = to!int(readValue()) != 0;
                catch (ConvException) dubHeader = false;
                break;
            case "use_FL_COMMAND":
                settings.useFlCommand = true;
                break;
            case "mergeback":
                try settings.writeMergebackData = to!int(readValue()) != 0;
                catch (ConvException) settings.writeMergebackData = false;
                break;
            case "do_not_include_H_from_C":
            case "utf8_in_src":
            case "avoid_early_includes":
                // C/C++ header-file flags with no D equivalent, see
                // `fluid.project_settings`.
                break;
            default:
                readValue();
                break;
            }
        }

        Node[] roots;
        while (true)
        {
            Node n = parseNode();
            if (n is null)
                break;
            roots ~= n;
        }
        return roots;
    }

    /// Ported from FLTK's `Fd_Shell_Command_List::read(Project_
    /// Reader*)` -- token-based (`readToken()`), not value-based
    /// (`readValue()` would balance-and-de-brace the whole `{ command
    /// {...} command {...} }` span as a single opaque string, which is
    /// wrong here: each nested `command {...}` needs its own real
    /// parse, not a flat text blob). Called with the "shell_commands"
    /// keyword token already consumed by `readProject()`'s own Options
    /// loop, matching `ShellCommand.readFrom(Reader)`'s own "keyword
    /// already consumed by the caller" convention.
    private void readShellCommands()
    {
        string open = readToken();
        if (open != "{") return;
        while (true)
        {
            string tok = readToken();
            if (tok is null || tok == "}") break;
            if (tok == "command")
            {
                auto cmd = new ShellCommand();
                cmd.readFrom(this);
                shellCommands ~= cmd;
            }
            else
                readValue(); // unknown -- skip its value defensively
        }
    }

    /// Ported from FLTK's `Layout_List::read(Project_Reader*)` --
    /// called with the "snap" keyword token already consumed by
    /// `readProject()`'s own Options loop, same convention as
    /// `readShellCommands()` just above. Each `suite { ... }` block
    /// becomes a real `LayoutSuite` (tagged `ToolStore.project` here,
    /// same as `readShellCommands()` tags every parsed command
    /// `ToolStore.project` before the caller decides what to do with
    /// it) -- `gui_main.d`'s `loadProject()` is the actual consumer,
    /// mirroring its own `shellCommands`-application shape exactly.
    /// FLTK's own "old style `snap N`, no braces -- ignore" fallback
    /// (a pre-`Layout_Suite` file format) is matched too: `readToken()`
    /// returning anything other than `"{"` just returns immediately,
    /// leaving `hasSnap` `false`.
    private void readSnap()
    {
        string open = readToken();
        if (open != "{") return;
        hasSnap = true;
        while (true)
        {
            string tok = readToken();
            if (tok is null) return;
            if (tok == "}") break;
            switch (tok)
            {
            case "ver":
                readValue();
                break;
            case "current_suite":
                layoutCurrentSuite = readValue();
                break;
            case "current_preset":
                try layoutCurrentPreset = to!int(readValue());
                catch (ConvException) layoutCurrentPreset = 0;
                break;
            case "suite":
                auto suite = new LayoutSuite("",
                    new LayoutPreset(), new LayoutPreset(), new LayoutPreset(),
                    ToolStore.project);
                suite.readFrom(this);
                layoutSuites ~= suite;
                break;
            default:
                readValue(); // unknown -- skip its value defensively
                break;
            }
        }
    }

    /// Parses one `TypeName instance_name { properties } [{ children }]`
    /// entry. Returns `null` on EOF or a stray `}` (the caller's own
    /// loop treats that as "end of this block"). `parent` is the
    /// already-in-progress enclosing node, if any -- needed *during*
    /// this node's own property-parsing loop (not just after, when
    /// `addChild()` would normally set `child.parent`) so a
    /// `parent_properties {}` block (see `fluid.node.Node.
    /// readParentProperty()`'s own doc comment) can reach the real
    /// parent while it's being read, before the child's subtree is
    /// even fully parsed.
    private Node parseNode(Node parent = null)
    {
        string typeName = readToken();
        if (typeName is null || typeName == "}")
            return null;

        string instanceName = readValue();

        Node node = createNode(typeName);
        node.typeName = typeName;
        node.instanceName = instanceName;

        string open = readToken();
        // `class <attribute> <name> {`: what was read as the name is the
        // attribute and the token after it is the real name.
        if (open != "{" && open !is null && node.acceptLeadingAttribute(instanceName))
        {
            instanceName = open;
            node.instanceName = instanceName;
            open = readToken();
        }
        if (open != "{") throw new Exception("fluid: expected '{' to start " ~ typeName ~ "'s property list");
        while (true)
        {
            string propName = readToken();
            if (propName is null || propName == "}")
                break;
            if (propName == "parent_properties")
            {
                string open2 = readToken();
                if (open2 != "{") throw new Exception("fluid: expected '{' to start parent_properties");
                while (true)
                {
                    string innerName = readToken();
                    if (innerName is null || innerName == "}")
                        break;
                    if (parent is null || !parent.readParentProperty(this, node, innerName))
                        readValue(); // same defensive-discard tolerance as below
                }
                continue;
            }
            if (!node.readProperty(this, propName))
            {
                // Unrecognized property -- consume one value word
                // defensively so parsing can keep going, matching
                // FLTK's own tolerant-of-unknown-properties spirit.
                readValue();
            }
        }

        if (node.canHaveChildren())
        {
            open = readToken();
            if (open != "{") throw new Exception("fluid: expected '{' to start " ~ typeName ~ "'s children");
            while (true)
            {
                Node child = parseNode(node);
                if (child is null)
                    break;
                node.addChild(child);
            }
        }

        return node;
    }
}
