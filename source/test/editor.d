// D transliteration of FLTK's test/editor.cxx.
// Build: rdmd buildsamples.d test editor
//
// FLTK is written as a progressive "FLTK Programmer's Guide" tutorial:
// ten `#if TUTORIAL_CHAPTER >= N` blocks that each layer more of the app on
// top of the last, gated behind a single `#define TUTORIAL_CHAPTER 10` so
// only the fully-assembled chapter-10 program (and its `main()`) actually
// compiles. D has no equivalent "compile only up through N" macro switch in
// use elsewhere in this project (`tile.d` picked one #if branch the same
// way), so this file transliterates the merged, chapter-10-only program --
// the tutorial-chapter comments are kept as section headers to preserve the
// provenance of each piece, but every `tutN_*` build function FLTK
// would call is folded together, matching what TUTORIAL_CHAPTER==10
// actually builds.
//
// This program touches a large amount of widget/dialog surface, all of
// it real, ported fldtk API used directly below: `DoubleWindow`,
// `MenuBar`/`MenuItem`, `TextBuffer`/`TextEditor`/`TextDisplay`,
// `NativeFileChooser`, `Flex`, `Tile`, `Input`/`Button`,
// `fl.hideAllWindows()`/`fl.argsToUtf8()`/`fl.args()`/`filenameName()`,
// and `fl_choice()`/`fl_alert()`/`fl_input()` (`fl.ask.choice()`/
// `fl.ask.alert()`/`fl.ask.fl_input()`).
//
// A few notes on this transliteration:
//  - `findIndex(Callback)` mirrors FLTK's `find_index(Fl_Callback*)`
//    overload; since fldtk callbacks are delegates (per CONVENTIONS.md)
//    rather than plain function pointers, each menu callback below is
//    given a named module-level `Callback` value (not an inline
//    literal) specifically so `findIndex()` has a stable delegate
//    identity to search for, the same role the C function pointer
//    played FLTK.
//  - `TextEditor.kfUndo`/`kfRedo`/`kfCut`/`kfCopy`/`kfPaste`/`kfDelete`
//    are transliterated as static methods taking the target
//    `TextEditor` (FLTK's `int (*)(int, Fl_Text_Editor*)` signature
//    drops its unused `int key` parameter).
//  - `fl_open_callback()` (FLTK's drag-a-file-onto-the-dock-icon
//    hook, `FL/platform.H`) takes a `void delegate(string)` in place of
//    FLTK's `void (*)(const char*)`.
//  - FLTK's per-call `strerror(errno)` (errno.h) is kept as-is; it's
//    plain C/POSIX, not FLTK API surface.
import fl;
import std.format : format;
import std.string : fromStringz;
import core.stdc.errno : errno;
import core.stdc.string : strerror;
import std.ascii : isDigit, isLower, isAlphaNum;

// ---- Tutorial Chapter 1 ------------------------------------------------
// Fl_Double_Window *app_window
DoubleWindow appWindow;

void tut1BuildAppWindow()
{
    appWindow = new DoubleWindow(640, 480, "FLTK Editor");
    appWindow.xclass("fl_editor");
}

// ---- Tutorial Chapter 2 -------------------------------------------------
MenuBar appMenuBar;
bool textChanged = false;
string appFilename = "";

void updateTitle()
{
    string fname = appFilename.length ? filenameName(appFilename) : null;
    if (fname.length)
    {
        string buf = textChanged ? format("%s *", fname) : fname;
        appWindow.copyLabel(buf);
    }
    else
    {
        appWindow.label("FLTK Editor");
    }
}

void setChanged(bool v)
{
    if (v != textChanged)
    {
        textChanged = v;
        updateTitle();
    }
}

void setFilename(string newFilename)
{
    appFilename = newFilename;
    updateTitle();
}

// Forward declared here (chapter 2), overridden for real in chapter 4 --
// FLTK does the same forward-declaration dance with a `#if
// TUTORIAL_CHAPTER < 4` guard; only the chapter-4-and-later definition
// further down is actually compiled/used.
void menuQuitCallback(Widget);

Callback menuQuitCallbackDg = (w) { menuQuitCallback(w); };

void tut2BuildAppMenuBar()
{
    appWindow.begin();
    appMenuBar = new MenuBar(0, 0, appWindow.w(), 25);
    appMenuBar.add("File/Quit Editor", stateCommand | 'q', menuQuitCallbackDg);
    appWindow.callback(menuQuitCallbackDg);
    appWindow.end();
}

// ---- Tutorial Chapter 3 -------------------------------------------------
TextEditor appEditor;
TextEditor appSplitEditor; // for later
TextBuffer appTextBuffer;

void textChangedCallback(int pos, int nInserted, int nDeleted, int nRestyled,
        const(char)[] deletedText)
{
    if (nInserted || nDeleted)
        setChanged(true);
}

Callback menuNewCallbackDg = (w) { menuNewCallback(w); };

void menuNewCallback(Widget)
{
    if (textChanged)
    {
        int c = choice("Changes in your text have not been saved.\n"
                ~ "Do you want to start a new text anyway?",
                "New", "Cancel", null);
        if (c == 1) return;
    }
    appTextBuffer.text("");
    setFilename(null);
    setChanged(false);
}

void tut3BuildMainEditor()
{
    appWindow.begin();
    appTextBuffer = new TextBuffer();
    appTextBuffer.addModifyCallback((pos, nInserted, nDeleted, nRestyled, deletedText) {
        textChangedCallback(pos, nInserted, nDeleted, nRestyled, deletedText);
    });
    appEditor = new TextEditor(0, appMenuBar.h(),
        appWindow.w(), appWindow.h() - appMenuBar.h());
    appEditor.buffer(appTextBuffer);
    appEditor.textfont(courier);
    appWindow.resizable(appEditor);
    appWindow.end();
    // find the Quit menu and insert the New menu there
    int ix = appMenuBar.findIndex(menuQuitCallbackDg);
    appMenuBar.insert(ix, "New", stateCommand | 'n', menuNewCallbackDg);
}

// ---- Tutorial Chapter 4 --------------------------------------------------
Callback menuSaveAsCallbackDg = (w) { menuSaveAsCallback(w); };
Callback menuSaveCallbackDg = (w) { menuSaveCallback(w); };
Callback menuOpenCallbackDg = (w) { menuOpenCallback(w); };

void menuSaveAsCallback(Widget)
{
    auto fileChooser = new NativeFileChooser();
    fileChooser.title("Save File As...");
    fileChooser.type(BrowseType.browseSaveFile);
    if (appFilename.length)
    {
        string name = filenameName(appFilename);
        if (name.length)
        {
            fileChooser.presetFile(name);
            fileChooser.directory(appFilename[0 .. $ - name.length]);
        }
    }
    if (fileChooser.show() == 0)
    {
        if (appTextBuffer.savefile(fileChooser.filename()) == 0)
        {
            setFilename(fileChooser.filename());
            setChanged(false);
        }
        else
        {
            alert(format("Failed to save file\n%s\n%s",
                fileChooser.filename(), fromStringz(strerror(errno))));
        }
    }
}

void menuSaveCallback(Widget)
{
    if (!appFilename.length)
    {
        menuSaveAsCallback(null);
    }
    else
    {
        if (appTextBuffer.savefile(appFilename) == 0)
        {
            setChanged(false);
        }
        else
        {
            alert(format("Failed to save file\n%s\n%s",
                appFilename, fromStringz(strerror(errno))));
        }
    }
}

// Real definition of menu_quit_callback (chapter 2's is only compiled for
// TUTORIAL_CHAPTER < 4; this one wins for chapter 10).
void menuQuitCallback(Widget)
{
    if (textChanged)
    {
        int r = choice("The current file has not been saved.\n"
                ~ "Would you like to save it now?",
                "Cancel", "Save", "Don't Save");
        if (r == 0) return; // cancel
        if (r == 1) // save
        {
            menuSaveCallback(null);
            return;
        }
    }
    fl.hideAllWindows();
}

void load(string filename)
{
    if (appTextBuffer.loadfile(filename) == 0)
    {
        setFilename(filename);
        setChanged(false);
    }
    else
    {
        alert(format("Failed to load file\n%s\n%s", filename, fromStringz(strerror(errno))));
    }
}

void menuOpenCallback(Widget)
{
    if (textChanged)
    {
        int r = choice("The current file has not been saved.\n"
                ~ "Would you like to save it now?",
                "Cancel", "Save", "Don't Save");
        if (r == 0) return; // cancel
        if (r == 1) menuSaveCallback(null); // save
    }
    auto fileChooser = new NativeFileChooser();
    fileChooser.title("Open File...");
    fileChooser.type(BrowseType.browseFile);
    if (appFilename.length)
    {
        string name = filenameName(appFilename);
        if (name.length)
        {
            fileChooser.presetFile(name);
            fileChooser.directory(appFilename[0 .. $ - name.length]);
        }
    }
    if (fileChooser.show() == 0)
        load(fileChooser.filename());
}

void tut4AddFileSupport()
{
    int ix = appMenuBar.findIndex(menuQuitCallbackDg);
    appMenuBar.insert(ix, "Open", stateCommand | 'o', menuOpenCallbackDg, menuDivider);
    appMenuBar.insert(ix + 1, "Save", stateCommand | 's', menuSaveCallbackDg);
    appMenuBar.insert(ix + 2, "Save as...", stateCommand | 'S', menuSaveAsCallbackDg, menuDivider);
}

int argsHandler(string[] args, ref int i)
{
    if (i < args.length && args[i].length && args[i][0] != '-')
    {
        load(args[i]);
        i++;
        return 1;
    }
    return 0;
}

int tut4HandleCommandlineAndRun(string[] args)
{
    int i = 0;
    fl.argsToUtf8(args);
    fl.args(args, i, (argv, ref j) => argsHandler(argv, j));
    openCallback((filename) { load(filename); });
    appWindow.show(args);
    fl.run();
    return 0;
}

// ---- Tutorial Chapter 5 -------------------------------------------------
void menuUndoCallback(Widget)
{
    Widget e = fl.focus();
    if (e !is null && (e is appEditor || e is appSplitEditor))
        TextEditor.kfUndo(0, cast(TextEditor) e);
}

void menuRedoCallback(Widget)
{
    Widget e = fl.focus();
    if (e !is null && (e is appEditor || e is appSplitEditor))
        TextEditor.kfRedo(0, cast(TextEditor) e);
}

void menuCutCallback(Widget)
{
    Widget e = fl.focus();
    if (e !is null && (e is appEditor || e is appSplitEditor))
        TextEditor.kfCut(0, cast(TextEditor) e);
}

void menuCopyCallback(Widget)
{
    Widget e = fl.focus();
    if (e !is null && (e is appEditor || e is appSplitEditor))
        TextEditor.kfCopy(0, cast(TextEditor) e);
}

void menuPasteCallback(Widget)
{
    Widget e = fl.focus();
    if (e !is null && (e is appEditor || e is appSplitEditor))
        TextEditor.kfPaste(0, cast(TextEditor) e);
}

void menuDeleteCallback(Widget)
{
    Widget e = fl.focus();
    if (e !is null && (e is appEditor || e is appSplitEditor))
        TextEditor.kfDelete(0, cast(TextEditor) e);
}

void tut5CutCopyPaste()
{
    appMenuBar.add("Edit/Undo", stateCommand | 'z', (w) { menuUndoCallback(w); });
    appMenuBar.add("Edit/Redo", stateCommand | 'Z', (w) { menuRedoCallback(w); }, menuDivider);
    appMenuBar.add("Edit/Cut", stateCommand | 'x', (w) { menuCutCallback(w); });
    appMenuBar.add("Edit/Copy", stateCommand | 'c', (w) { menuCopyCallback(w); });
    appMenuBar.add("Edit/Paste", stateCommand | 'v', (w) { menuPasteCallback(w); });
    appMenuBar.add("Edit/Delete", 0, (w) { menuDeleteCallback(w); });
}

// ---- Tutorial Chapter 6 -------------------------------------------------
string lastFindText = "";

bool findNext(string needle)
{
    TextEditor editor = appEditor;
    Widget e = fl.focus();
    if (e !is null && e is appSplitEditor)
        editor = appSplitEditor;
    int pos = editor.insertPosition();
    int found = appTextBuffer.searchForward(pos, needle, pos);
    if (found)
    {
        appTextBuffer.select(pos, pos + cast(int) needle.length);
        editor.insertPosition(pos + cast(int) needle.length);
        editor.showInsertPosition();
        return true;
    }
    else
    {
        alert(format("No further occurrences of '%s' found!", needle));
        return false;
    }
}

void menuFindCallback(Widget)
{
    string findText = fl_input("Find in text:", lastFindText);
    if (findText !is null)
    {
        lastFindText = findText;
        findNext(findText);
    }
}

void menuFindNextCallback(Widget)
{
    if (lastFindText.length)
        findNext(lastFindText);
    else
        menuFindCallback(null);
}

void tut6ImplementFind()
{
    appMenuBar.add("Find/Find...", stateCommand | 'f', (w) { menuFindCallback(w); });
    appMenuBar.add("Find/Find Next", stateCommand | 'g', (w) { menuFindNextCallback(w); }, menuDivider);
}

// ---- Tutorial Chapter 7 -------------------------------------------------
string lastReplaceText = "";

void replaceSelection(string newText)
{
    TextEditor editor = appEditor;
    Widget e = fl.focus();
    if (e !is null && e is appSplitEditor)
        editor = appSplitEditor;
    int start, end;
    if (appTextBuffer.selectionPosition(start, end))
    {
        appTextBuffer.removeSelection();
        appTextBuffer.insert(start, newText);
        appTextBuffer.select(start, start + cast(int) newText.length);
        editor.insertPosition(start + cast(int) newText.length);
        editor.showInsertPosition();
    }
}

class ReplaceDialog : DoubleWindow
{
    private Input findTextInput;
    private Input replaceTextInput;
    private Button findNextButton;
    private Button replaceAndFindButton;
    private Button closeButton;

    this(string label)
    {
        super(430, 110, label);
        findTextInput = new Input(100, 10, 320, 25, "Find:");
        replaceTextInput = new Input(100, 40, 320, 25, "Replace:");
        auto buttonField = new Flex(100, 70, w() - 100, 40);
        buttonField.type(flexHorizontal);
        buttonField.margin(0, 5, 10, 10);
        buttonField.gap(10);
        findNextButton = new Button(0, 0, 0, 0, "Next");
        findNextButton.callback((w) { findNextCallback(w); });
        replaceAndFindButton = new Button(0, 0, 0, 0, "Replace");
        replaceAndFindButton.callback((w) { replaceAndFindCallback(w); });
        closeButton = new Button(0, 0, 0, 0, "Close");
        closeButton.callback((w) { closeCallback(w); });
        buttonField.end();
        setNonModal();
    }

    override void show()
    {
        findTextInput.value(lastFindText);
        replaceTextInput.value(lastReplaceText);
        super.show();
    }

    private void findNextCallback(Widget)
    {
        lastFindText = findTextInput.value();
        lastReplaceText = replaceTextInput.value();
        if (lastFindText.length)
            findNext(lastFindText);
    }

    private void replaceAndFindCallback(Widget w)
    {
        replaceSelection(replaceTextInput.value());
        findNextCallback(w);
    }

    private void closeCallback(Widget)
    {
        hide();
    }
}

ReplaceDialog replaceDialog;

void menuReplaceCallback(Widget)
{
    if (replaceDialog is null)
        replaceDialog = new ReplaceDialog("Find and Replace");
    replaceDialog.show();
}

void menuReplaceNextCallback(Widget)
{
    if (!lastFindText.length)
    {
        menuReplaceCallback(null);
    }
    else
    {
        replaceSelection(lastReplaceText);
        findNext(lastFindText);
    }
}

void tut7ImplementReplace()
{
    appMenuBar.add("Find/Replace...", stateCommand | 'r', (w) { menuReplaceCallback(w); });
    appMenuBar.add("Find/Replace Next", stateCommand | 't', (w) { menuReplaceNextCallback(w); });
}

// ---- Tutorial Chapter 8 -------------------------------------------------
void menuLinenumbersCallback(Widget w)
{
    auto menu = cast(MenuBar) w;
    const(MenuItem)* linenumberItem = menu.mvalue();
    if (linenumberItem.value())
        appEditor.linenumberWidth(40);
    else
        appEditor.linenumberWidth(0);
    appEditor.redraw();
    if (appSplitEditor !is null)
    {
        if (linenumberItem.value())
            appSplitEditor.linenumberWidth(40);
        else
            appSplitEditor.linenumberWidth(0);
        appSplitEditor.redraw();
    }
}

void menuWordwrapCallback(Widget w)
{
    auto menu = cast(MenuBar) w;
    const(MenuItem)* wordwrapItem = menu.mvalue();
    if (wordwrapItem.value())
        appEditor.wrapMode(WrapMode.wrapAtBounds, 0);
    else
        appEditor.wrapMode(WrapMode.wrapNone, 0);
    appEditor.redraw();
    if (appSplitEditor !is null)
    {
        if (wordwrapItem.value())
            appSplitEditor.wrapMode(WrapMode.wrapAtBounds, 0);
        else
            appSplitEditor.wrapMode(WrapMode.wrapNone, 0);
        appSplitEditor.redraw();
    }
}

void tut8EditorFeatures()
{
    appMenuBar.add("Window/Line Numbers", stateCommand | 'l', (w) { menuLinenumbersCallback(w); }, menuToggle);
    appMenuBar.add("Window/Word Wrap", 0, (w) { menuWordwrapCallback(w); }, menuToggle);
}

// ---- Tutorial Chapter 9 -------------------------------------------------
Tile appTile;

void menuSplitCallback(Widget w)
{
    auto menu = cast(MenuBar) w;
    const(MenuItem)* splitviewItem = menu.mvalue();
    if (splitviewItem.value())
    {
        int hSplit = appTile.h() / 2;
        appEditor.size(appTile.w(), hSplit);
        appSplitEditor.resize(appTile.x(), appTile.y() + hSplit,
            appTile.w(), appTile.h() - hSplit);
        appSplitEditor.show();
    }
    else
    {
        appEditor.size(appTile.w(), appTile.h());
        appSplitEditor.resize(appTile.x(), appTile.y() + appTile.h(),
            appTile.w(), 0);
        appSplitEditor.hide();
    }
    appTile.resizable(appEditor);
    appTile.initSizes();
    appTile.redraw();
}

void tut9SplitEditor()
{
    appWindow.begin();
    appTile = new Tile(appEditor.x(), appEditor.y(), appEditor.w(), appEditor.h());
    appWindow.remove(appEditor);
    appTile.add(appEditor);
    appSplitEditor = new TextEditor(appTile.x(), appTile.y() + appTile.h(),
        appTile.w(), 0);
    appSplitEditor.buffer(appTextBuffer);
    appSplitEditor.textfont(courier);
    appSplitEditor.hide();
    appTile.end();
    appTile.sizeRange(0, 25, 25);
    appTile.sizeRange(1, 25, 25);
    appTile.initSizes();
    appWindow.end();
    appWindow.resizable(appTile);
    appTile.resizable(appEditor);
    appMenuBar.add("Window/Split", stateCommand | 'i', (w) { menuSplitCallback(w); }, menuToggle);
}

// ---- Tutorial Chapter 10 -------------------------------------------------
TextBuffer appStyleBuffer;

// Syntax highlighting stuff...
enum int ts = 14; // default editor textsize

StyleTableEntry[] styletable = [
    // FONT COLOR     FONT FACE     FONT SIZE
    StyleTableEntry(black, courier, ts), // A - Plain
    StyleTableEntry(darkGreen, helveticaItalic, ts), // B - Line comments
    StyleTableEntry(darkGreen, helveticaItalic, ts), // C - Block comments
    StyleTableEntry(blue, courier, ts), // D - Strings
    StyleTableEntry(darkRed, courier, ts), // E - Directives
    StyleTableEntry(darkRed, courierBold, ts), // F - Types
    StyleTableEntry(blue, courierBold, ts), // G - Keywords
];

immutable(string)[] codeKeywords = [
    "and", "and_eq", "asm", "bitand", "bitor", "break", "case", "catch",
    "compl", "continue", "default", "delete", "do", "else", "false", "for",
    "goto", "if", "new", "not", "not_eq", "operator", "or", "or_eq",
    "return", "switch", "template", "this", "throw", "true", "try",
    "while", "xor", "xor_eq",
];

immutable(string)[] codeTypes = [
    "auto", "bool", "char", "class", "const", "const_cast", "double",
    "dynamic_cast", "enum", "explicit", "extern", "float", "friend",
    "inline", "int", "long", "mutable", "namespace", "private", "protected",
    "public", "register", "short", "signed", "sizeof", "static",
    "static_cast", "struct", "template", "typedef", "typename", "union",
    "unsigned", "virtual", "void", "volatile",
];

// 'styleParse()' - Parse text and produce style data.
//
// Style letters:
//  A - Plain, B - Line comments, C - Block comments, D - Strings,
//  E - Directives, F - Types, G - Keywords
void styleParse(string text, char[] style)
{
    import std.algorithm : countUntil;

    char current = style.length ? style[0] : 'A';
    int col = 0;
    bool last = false;
    size_t i = 0;
    size_t length = text.length;

    while (length > 0)
    {
        if (current == 'B' || current == 'F' || current == 'G')
            current = 'A';

        if (current == 'A')
        {
            if (col == 0 && text[i] == '#')
            {
                current = 'E';
            }
            else if (length >= 2 && text[i .. i + 2] == "//")
            {
                current = 'B';
                while (length > 0 && text[i] != '\n')
                {
                    style[i] = 'B';
                    i++;
                    length--;
                }
                if (length == 0) break;
                continue;
            }
            else if (length >= 2 && text[i .. i + 2] == "/*")
            {
                current = 'C';
            }
            else if (length >= 2 && text[i .. i + 2] == "\\\"")
            {
                style[i] = current;
                style[i + 1] = current;
                i += 2;
                length -= 2;
                col += 2;
                continue;
            }
            else if (text[i] == '"')
            {
                current = 'D';
            }
            else if (!last && (isLower(text[i]) || text[i] == '_'))
            {
                size_t j = i;
                while (j < text.length && (isLower(text[j]) || text[j] == '_'))
                    j++;
                string word = text[i .. j];
                bool isType = codeTypes.countUntil(word) >= 0;
                bool isKeyword = !isType && codeKeywords.countUntil(word) >= 0;
                if (isType || isKeyword)
                {
                    char c = isType ? 'F' : 'G';
                    while (i < j)
                    {
                        style[i] = c;
                        i++;
                        length--;
                        col++;
                    }
                    last = true;
                    continue;
                }
            }
        }
        else if (current == 'C' && length >= 2 && text[i .. i + 2] == "*/")
        {
            style[i] = current;
            style[i + 1] = current;
            i += 2;
            length -= 2;
            current = 'A';
            col += 2;
            continue;
        }
        else if (current == 'D')
        {
            if (length >= 2 && text[i .. i + 2] == "\\\"")
            {
                style[i] = current;
                style[i + 1] = current;
                i += 2;
                length -= 2;
                col += 2;
                continue;
            }
            else if (text[i] == '"')
            {
                style[i] = current;
                col++;
                current = 'A';
                i++;
                length--;
                continue;
            }
        }

        if (current == 'A' && (text[i] == '{' || text[i] == '}'))
            style[i] = 'G';
        else
            style[i] = current;
        col++;

        last = isAlphaNum(text[i]) || text[i] == '_' || text[i] == '.';

        if (text[i] == '\n')
        {
            col = 0;
            if (current == 'B' || current == 'E') current = 'A';
        }

        i++;
        length--;
    }
}

// 'styleInit()' - Initialize the style buffer...
void styleInit()
{
    string text = appTextBuffer.text();
    char[] style;
    style.length = text.length;
    style[] = 'A';

    if (appStyleBuffer is null)
        appStyleBuffer = new TextBuffer(cast(int) text.length);

    styleParse(text, style);

    appStyleBuffer.text(cast(string) style);
}

// 'styleUnfinishedCb()' - Update unfinished styles.
void styleUnfinishedCb(int)
{
}

// 'styleUpdate()' - Update the style buffer...
void styleUpdate(int pos, int nInserted, int nDeleted, int nRestyled,
        const(char)[] deletedText, TextEditor editor)
{
    // If this is just a selection change, just unselect the style buffer...
    if (nInserted == 0 && nDeleted == 0)
    {
        appStyleBuffer.unselect();
        return;
    }

    // Track changes in the text buffer...
    if (nInserted > 0)
    {
        char[] style;
        style.length = nInserted;
        style[] = 'A';
        appStyleBuffer.replace(pos, pos + nDeleted, cast(string) style);
    }
    else
    {
        appStyleBuffer.remove(pos, pos + nDeleted);
    }

    // Select the area that was just updated to avoid unnecessary callbacks...
    appStyleBuffer.select(pos, pos + nInserted - nDeleted);

    // Re-parse the changed region...
    int start = appTextBuffer.lineStart(pos);
    int end = appTextBuffer.lineEnd(pos + nInserted);
    string text = appTextBuffer.textRange(start, end);
    char[] style = cast(char[]) appStyleBuffer.textRange(start, end).dup;
    char last = (start == end) ? cast(char) 0 : style[$ - 1];

    styleParse(text, style);

    appStyleBuffer.replace(start, end, cast(string) style);
    editor.redisplayRange(start, end);

    if (start == end || last != style[$ - 1])
    {
        // Either the user deleted some text, or the last character on the
        // line changed styles, so reparse the remainder of the buffer...
        end = appTextBuffer.length();
        text = appTextBuffer.textRange(start, end);
        style = cast(char[]) appStyleBuffer.textRange(start, end).dup;

        styleParse(text, style);

        appStyleBuffer.replace(start, end, cast(string) style);
        editor.redisplayRange(start, end);
    }
}

// Named, persistent delegate (not an inline literal) so removeModifyCallback()
// below has a stable identity to match against -- TextModifyCb has no
// separate userdata slot (delegates already capture context), so
// appEditor is baked in here instead of passed through per-call.
TextModifyCb styleUpdateCb;

void menuSyntaxhighlightCallback(Widget w)
{
    auto menu = cast(MenuBar) w;
    const(MenuItem)* syntaxItem = menu.mvalue();
    if (syntaxItem.value())
    {
        styleInit();
        appEditor.highlightData(appStyleBuffer, styletable, 'A',
            (code) { styleUnfinishedCb(code); });
        if (styleUpdateCb is null)
            styleUpdateCb = (pos, nInserted, nDeleted, nRestyled, deletedText) {
                styleUpdate(pos, nInserted, nDeleted, nRestyled, deletedText, appEditor);
            };
        appTextBuffer.addModifyCallback(styleUpdateCb);
    }
    else
    {
        appTextBuffer.removeModifyCallback(styleUpdateCb);
        appEditor.highlightData(null, null, 'A', null);
    }
    appEditor.redraw();
    if (appSplitEditor !is null)
    {
        if (syntaxItem.value())
        {
            appSplitEditor.highlightData(appStyleBuffer, styletable, 'A',
                (code) { styleUnfinishedCb(code); });
        }
        else
        {
            appSplitEditor.highlightData(null, null, 'A', null);
        }
        appSplitEditor.redraw();
    }
}

void tut10SyntaxHighlighting()
{
    appMenuBar.add("Window/Syntax Highlighting", 0, (w) { menuSyntaxhighlightCallback(w); }, menuToggle);
}

// ---- main -----------------------------------------------------------------
void main(string[] args)
{
    tut1BuildAppWindow();
    tut2BuildAppMenuBar();
    tut3BuildMainEditor();
    tut4AddFileSupport();
    tut5CutCopyPaste();
    tut6ImplementFind();
    tut7ImplementReplace();
    tut8EditorFeatures();
    tut9SplitEditor();
    tut10SyntaxHighlighting();
    tut4HandleCommandlineAndRun(args);
}
