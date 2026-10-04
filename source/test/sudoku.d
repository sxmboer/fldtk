// D transliteration of FLTK's test/sudoku.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh sudoku
//
// Notes on this transliteration:
//  - Fl_Sys_Menu_Bar/Fl_Menu_Item (SysMenuBar/MenuItem), Fl_Help_Dialog
//    (HelpDialog), Fl_Preferences (Preferences), Fl_Image_Surface/
//    Fl_Surface_Device (ImageSurface/SurfaceDevice), Fl_Bitmap (Bitmap),
//    Fl::fl_alert() (fl.ask.alert()), and Fl::fl_choice()
//    (fl.ask.choice()) are all real, ported fldtk API, used directly
//    below.
//  - FLTK's Fl_Menu_Item callback is a function pointer plus a
//    void* user_data (here, ASCII '0'-'3' difficulty strings decoded
//    with atoi()); per CLAUDE.md's callback convention this becomes a
//    D delegate that just captures the difficulty level directly,
//    dropping the user_data/atoi indirection entirely.
//  - SudokuSound is transliterated against the ALSA branch only
//    (FLTK also has CoreAudio/Win32/X11-bell branches selected by
//    #ifdef) since Linux is this project's primary target (see
//    CLAUDE.md); no ALSA bindings exist in fldtk yet, so the snd_pcm_*
//    calls are kept verbatim but wrapped in version(none) so this
//    sample still compiles -- flip to version(all) once ALSA bindings
//    exist.
import fl;
import std.format : format;
import std.math : sin, PI;
import std.random : uniform, rndGen, unpredictableSeed;

//
// Default sizes...
//
enum int GROUP_SIZE = 160;
enum int CELL_SIZE = 50;
enum int CELL_OFFSET = 5;
enum int MENU_OFFSET = 25; // non-macOS: Linux is this project's primary target

// Sound class for Sudoku -- see the file header note: ALSA branch only.
class SudokuSound
{
    // No ALSA bindings exist in fldtk yet;
    // the real snd_pcm_* code below is kept verbatim, gated behind
    // version(none) so it still compiles once those bindings land --
    // flip this to version(all) at that point to bring it back and
    // verify it against real hardware. Not a permanent removal: the end
    // target is a complete port, sound included.
    version (none)
    {
        private snd_pcm_t* handle_;
    }

    // Common data...
    static immutable int[9] frequencies = [
        880,  // A(5)
        988,  // B(5)
        1046, // C(5)
        1174, // D(5)
        1318, // E(5)
        1396, // F(5)
        1568, // G(5)
        1760, // H (A6)
        1976  // I (B6)
    ];
    static short[][9] sampleData;
    static int sampleSize;

    this()
    {
        sampleSize = 0;

        version (none)
        {
            handle_ = null;

            if (snd_pcm_open(&handle_, "default", SndPcmStream.playback, 0) >= 0)
            {
                SndPcmHwParamsT* params;
                snd_pcm_hw_params_alloca(&params);
                snd_pcm_hw_params_any(handle_, params);
                snd_pcm_hw_params_set_access(handle_, params, SndPcmAccess.rwInterleaved);
                snd_pcm_hw_params_set_format(handle_, params, SndPcmFormat.s16);
                snd_pcm_hw_params_set_channels(handle_, params, 2);
                uint rate = 44100;
                int dir;
                snd_pcm_hw_params_set_rate_near(handle_, params, &rate, &dir);
                auto period = cast(snd_pcm_uframes_t)(rate / 4);
                snd_pcm_hw_params_set_period_size_near(handle_, params, &period, &dir);

                sampleSize = rate / 20;

                if (snd_pcm_hw_params(handle_, params) < 0)
                {
                    sampleSize = 0;
                    snd_pcm_close(handle_);
                    handle_ = null;
                }
            }
        }

        if (sampleSize)
        {
            // Make each of the notes using a combination of sine and sawtooth waves
            int attack = sampleSize / 10;
            int decay = 4 * sampleSize / 5;

            for (int i = 0; i < 9; i++)
            {
                sampleData[i] = new short[2 * sampleSize];

                for (int j = 0; j < sampleSize; j++)
                {
                    double theta = 0.05 * frequencies[i] * j / sampleSize;
                    double val = 0.5 * sin(2.0 * PI * theta) + theta - cast(int) theta - 0.5;
                    short sample;

                    if (j < attack)
                        sample = cast(short)(32767 * val * j / attack);
                    else if (j > decay)
                        sample = cast(short)(32767 * val * (sampleSize - j + decay) / sampleSize);
                    else
                        sample = cast(short)(32767 * val);

                    sampleData[i][2 * j] = sample;
                    sampleData[i][2 * j + 1] = sample;
                }
            }
        }
    }

    ~this()
    {
        version (none)
        {
            if (handle_ !is null)
            {
                snd_pcm_drain(handle_);
                snd_pcm_close(handle_);
            }
        }
    }

    enum int NOTE_DURATION = 50;

    // Play a note for <NOTE_DURATION> ms...
    void play(char note)
    {
        fl.check();

        version (none)
        {
            if (handle_ !is null)
            {
                // Use ALSA to play the sound...
                if (snd_pcm_writei(handle_, sampleData[note - 'A'].ptr, sampleSize) < 0)
                {
                    snd_pcm_prepare(handle_);
                    snd_pcm_writei(handle_, sampleData[note - 'A'].ptr, sampleSize);
                }
            }
        }
    }
}

alias State = uint;
alias GameState = State[81];

// Sudoku cell class...
class SudokuCell : Widget
{
    private int row_;
    private int col_;
    private bool readonly_;
    private int value_;
    private int hintMap_;

    this(int row, int col, int X, int Y, int W, int H)
    {
        super(X, Y, W, H, null);
        row_ = row;
        col_ = col;
        value(0);
    }

    int row() { return row_; }
    int col() { return col_; }

    // Draw cell
    override void draw()
    {
        static immutable Align[9] alignTable = [
            alignTopLeft,
            alignTop,
            alignTopRight,
            alignLeft,
            0,
            alignRight,
            alignBottomLeft,
            alignBottom,
            alignBottomRight,
        ];

        // Draw the cell box...
        if (readonly())
            drawBoxAt(Boxtype.upBox, x(), y(), w(), h(), color());
        else
            drawBoxAt(Boxtype.downBox, x(), y(), w(), h(), color());

        // Draw the cell background...
        if (fl.focus() is this)
        {
            // fl.enumerations.selectionColor: the FL_SELECTION_COLOR
            // constant (blue), not this widget's own selectionColor()
            // accessor below (which defaults to plain gray, matching
            // FLTK's Fl_Widget::selection_color_ = FL_GRAY) -- same
            // ambiguity already hit and fixed in fl.light_button.
            Color c = colorAverage(fl.enumerations.selectionColor, color(), 0.5f);
            fl_color(c);
            fl_rectf(x() + 4, y() + 4, w() - 8, h() - 8);
            fl_color(contrast(labelcolor(), c));
        }
        else
            fl_color(labelcolor());

        // Draw the cell value...
        char[2] s;
        s[1] = '\0';

        if (value_)
        {
            s[0] = cast(char)(value_ + '0');
            fl_font(helveticaBold, h() - 10);
            fl_draw(s[0 .. 1].idup, x(), y(), w(), h(), alignCenter);
        }
        else
        {
            fl_font(helveticaBold, h() / 5);
            for (int i = 1; i <= 9; i++)
            {
                if (hintSet(i))
                {
                    s[0] = cast(char)(i + '0');
                    fl_draw(s[0 .. 1].idup, x() + 5, y() + 5, w() - 10, h() - 10, alignTable[i - 1]);
                }
            }
        }
    }

    // Handle events in cell
    override int handle(Event event)
    {
        switch (event)
        {
        case Event.focus:
            fl.focus(this);
            redraw();
            return 1;

        case Event.unfocus:
            redraw();
            return 1;

        case Event.push:
            if (!readonly() && fl.eventInside(this))
            {
                if (fl.eventClicks())
                {
                    // 2+ clicks increments/sets value
                    if (value())
                    {
                        if (value() < 9) value(value() + 1);
                        else value(1);
                    }
                    else value(sudoku.nextValue(this));
                }
                // TODO: add this to the undo process
                fl.focus(this);
                redraw();
                return 1;
            }
            break;

        case keyboard:
            if (fl.eventState() & stateCtrl) break;
            int key = fl.eventKey() - '0';
            if (key < 0 || key > 9) key = fl.eventKey() - kp - '0';
            if (key > 0 && key <= 9)
            {
                if (readonly())
                {
                    fl_beep(Beep.error);
                    return 1;
                }

                if (fl.eventState() & (stateShift | stateCapsLock))
                {
                    if (hintSet(key)) clearHint(key);
                    else setHint(key);
                    sudoku.undoCheckpoint();
                    redraw();
                }
                else
                {
                    value(key);
                    sudoku.clearHintsFor(row(), col(), key);
                    sudoku.undoCheckpoint();
                    doCallback();
                }
                return 1;
            }
            else if (key == 0 || fl.eventKey() == backSpace || fl.eventKey() == deleteKey)
            {
                if (readonly())
                {
                    fl_beep(Beep.error);
                    return 1;
                }
                if (fl.eventState() & (stateShift | stateCapsLock))
                {
                    clearHints();
                    sudoku.undoCheckpoint();
                }
                else
                {
                    value(0);
                    doCallback();
                    sudoku.undoCheckpoint();
                }
                return 1;
            }
            break;

        default:
            break;
        }

        return super.handle(event);
    }

    void readonly(bool r) { readonly_ = r; redraw(); }
    bool readonly() const { return readonly_; }
    void setHint(int n) { hintMap_ |= (1 << n); redraw(); }
    void clearHint(int n) { hintMap_ &= ~(1 << n); redraw(); }
    void clearHints() { hintMap_ = 0; redraw(); }
    void setHintMap(int v) { hintMap_ = v; }
    int getHintMap() { return hintMap_; }
    bool hintSet(int n) const { return (hintMap_ & (1 << n)) != 0; }
    void value(int v) { value_ = v; redraw(); }
    int value() const { return value_; }

    State state()
    {
        return cast(State)((hintMap_ >> 1) | (value_ << 12) | (readonly_ << 9));
    }

    void state(State s)
    {
        hintMap_ = (s & 0x000001ff) << 1;
        readonly_ = ((s & 0x00000200) >> 9) != 0;
        value_ = (s & 0x0000f000) >> 12;
        if (readonly_) color(gray); else color(light3);
        redraw();
    }
}

// Sudoku window class...
class Sudoku : DoubleWindow
{
    private SysMenuBar menubar_;
    private FlGroup grid_;
    private long seed_;
    private char[9][9] gridValues_;
    private SudokuCell[9][9] gridCells_;
    private FlGroup[3][3] gridGroups_;
    private int difficulty_;
    private SudokuSound sound_;
    private GameState[64] undoStack;
    private int undoHead_, undoTail_, redoHead_;

    private static HelpDialog helpDialog_;
    private static Preferences prefs_;

    static this()
    {
        prefs_ = new Preferences(rootUserL, "fltk.org", "sudoku");
    }

    this()
    {
        super(GROUP_SIZE * 3, GROUP_SIZE * 3 + MENU_OFFSET, "Sudoku");
        undoHead_ = 0;
        undoTail_ = 0;
        redoHead_ = 0;

        int j, k;

        MenuItem[] items = [
            MenuItem("&Game", 0, null, menuSubmenu),
            MenuItem("&New Game", stateCommand | 'n', (w) { newCb(w); }, menuDivider),
            MenuItem("&Check Game", stateCommand | 'c', (w) { checkCb(w); }, 0),
            MenuItem("&Restart Game", stateCommand | 'r', (w) { restartCb(w); }, 0),
            MenuItem("&Solve Game", stateCommand | 's', (w) { solveCb(w); }, menuDivider),
            MenuItem("&Update Helpers", 0, (w) { updateHelpersCb(w); }, 0),
            MenuItem("&Mute Sound", stateCommand | 'm', (w) { muteCb(w); }, menuToggle | menuDivider),
            MenuItem("&Quit", stateCommand | 'q', (w) { closeCb(w); }, 0),
            MenuItem(null, 0, null, 0),
            MenuItem("&Edit", 0, null, menuSubmenu),
            MenuItem("&Undo", stateCommand | 'z', (w) { undoCb(w); }, 0),
            MenuItem("&Redo", stateCommand | 'Z', (w) { redoCb(w); }, 0),
            MenuItem(null, 0, null, 0),
            MenuItem("&Difficulty", 0, null, menuSubmenu),
            MenuItem("&Easy", 0, (w) { diffCb(0); }, menuRadio),
            MenuItem("&Medium", 0, (w) { diffCb(1); }, menuRadio),
            MenuItem("&Hard", 0, (w) { diffCb(2); }, menuRadio),
            MenuItem("&Impossible", 0, (w) { diffCb(3); }, menuRadio),
            MenuItem(null, 0, null, 0),
            MenuItem("&Help", 0, null, menuSubmenu),
            MenuItem("&About Sudoku", f + 1, (w) { helpCb(w); }, 0),
            MenuItem(null, 0, null, 0),
            MenuItem(null, 0, null, 0),
        ];

        // Setup sound output...
        prefs_.get("mute_sound", j, 0);
        if (j)
        {
            // Mute sound?
            sound_ = null;
            items[6].flags |= menuValue;
        }
        else sound_ = new SudokuSound();

        // Menubar...
        prefs_.get("difficulty", difficulty_, 0);
        if (difficulty_ < 0 || difficulty_ > 3) difficulty_ = 0;

        items[14 + difficulty_].flags |= menuValue;

        menubar_ = new SysMenuBar(0, 0, 3 * GROUP_SIZE, 25);
        menubar_.menu(items);

        // Create the grids...
        grid_ = new FlGroup(0, MENU_OFFSET, 3 * GROUP_SIZE, 3 * GROUP_SIZE);

        for (j = 0; j < 3; j++)
            for (k = 0; k < 3; k++)
            {
                FlGroup g = new FlGroup(k * GROUP_SIZE, j * GROUP_SIZE + MENU_OFFSET,
                                     GROUP_SIZE, GROUP_SIZE);
                g.box(Boxtype.borderBox);
                if ((j == 1) ^ (k == 1)) g.color(dark3);
                else g.color(dark2);
                g.end();

                gridGroups_[j][k] = g;
            }

        for (j = 0; j < 9; j++)
            for (k = 0; k < 9; k++)
            {
                auto cell = new SudokuCell(j, k,
                    k * CELL_SIZE + CELL_OFFSET + (k / 3) * (GROUP_SIZE - 3 * CELL_SIZE),
                    j * CELL_SIZE + CELL_OFFSET + MENU_OFFSET + (j / 3) * (GROUP_SIZE - 3 * CELL_SIZE),
                    CELL_SIZE, CELL_SIZE);
                cell.callback((w) { resetCb(w); });
                gridCells_[j][k] = cell;
            }
        grid_.end();

        // Set icon for window
        auto bm = new Bitmap(sudokuBits, sudokuWidth, sudokuHeight);
        auto surf = new ImageSurface(sudokuWidth, sudokuHeight, 1);
        SurfaceDevice.pushCurrent(surf);
        fl_color(white);
        fl_rectf(0, 0, sudokuWidth, sudokuHeight);
        fl_color(black);
        bm.draw(0, 0);
        SurfaceDevice.popCurrent();
        icon(surf.image());

        // Catch window close events...
        callback((w) { closeCb(w); });

        // Make the window resizable...
        resizable(grid_);
        sizeRange(3 * GROUP_SIZE, 3 * GROUP_SIZE + MENU_OFFSET, 0, 0, 5, 5, 1);

        // Restore the previous window dimensions...
        int X, Y, W, H;

        if (prefs_.get("x", X, -1))
        {
            prefs_.get("y", Y, -1);
            prefs_.get("width", W, 3 * GROUP_SIZE);
            prefs_.get("height", H, 3 * GROUP_SIZE + MENU_OFFSET);

            resize(X, Y, W, H);
        }

        setTitle();
        clearUndo();
    }

    ~this()
    {
        if (sound_ !is null) destroy(sound_);
    }

    // Check for a solution to the game...
    private void checkCb(Widget widget)
    {
        sudoku.checkGame();
    }

    // Check if the user has correctly solved the game...
    void checkGame(bool highlight = true)
    {
        bool empty = false;
        bool correct = true;
        int j, k, m;

        // Check the game for right/wrong answers...
        for (j = 0; j < 9; j++)
            for (k = 0; k < 9; k++)
            {
                SudokuCell cell = gridCells_[j][k];
                int val = cell.value();

                if (cell.readonly()) continue;

                if (!val) empty = true;
                else
                {
                    for (m = 0; m < 9; m++)
                        if ((j != m && gridCells_[m][k].value() == val) ||
                            (k != m && gridCells_[j][m].value() == val)) break;

                    if (m < 9)
                    {
                        if (highlight)
                        {
                            cell.color(yellow);
                            cell.redraw();
                        }

                        correct = false;
                    }
                    else if (highlight)
                    {
                        cell.color(light3);
                        cell.redraw();
                    }
                }
            }

        // Check subgrids for duplicate numbers...
        for (j = 0; j < 9; j += 3)
            for (k = 0; k < 9; k += 3)
                for (int jj = 0; jj < 3; jj++)
                    for (int kk = 0; kk < 3; kk++)
                    {
                        SudokuCell cell = gridCells_[j + jj][k + kk];
                        int val = cell.value();

                        if (cell.readonly() || !val) continue;

                        int jjj;

                        for (jjj = 0; jjj < 3; jjj++)
                        {
                            int kkk;

                            for (kkk = 0; kkk < 3; kkk++)
                                if (jj != jjj && kk != kkk &&
                                    gridCells_[j + jjj][k + kkk].value() == val) break;

                            if (kkk < 3) break;
                        }

                        if (jjj < 3)
                        {
                            if (highlight)
                            {
                                cell.color(yellow);
                                cell.redraw();
                            }

                            correct = false;
                        }
                    }

        if (!empty && correct)
        {
            // Success!
            for (j = 0; j < 9; j++)
            {
                for (k = 0; k < 9; k++)
                {
                    SudokuCell cell = gridCells_[j][k];
                    cell.color(green);
                    cell.readonly(true);
                }

                if (sound_ !is null)
                    sound_.play(cast(char)('A' + gridCells_[j][8].value() - 1));
            }
        }
    }

    // Close the window, saving the game first...
    private void closeCb(Widget widget)
    {
        sudoku.saveGame();
        sudoku.hide();

        if (helpDialog_ !is null) helpDialog_.hide();
    }

    // Set the level of difficulty...
    private void diffCb(int diff)
    {
        if (diff != sudoku.difficulty_)
        {
            sudoku.difficulty_ = diff;
            sudoku.newGame(unpredictableSeed);
            sudoku.setTitle();

            if (diff > 1)
            {
                // Display a message about the higher difficulty levels for the
                // Sudoku zealots of the world...
                int val;

                prefs_.get("difficulty_warning", val, 0);

                if (!val)
                {
                    prefs_.set("difficulty_warning", 1);
                    alert("Note: 'Hard' and 'Impossible' puzzles may have more than " ~
                             "one possible solution.\n" ~
                             "This is not an error or bug.");
                }
            }

            prefs_.set("difficulty", sudoku.difficulty_);
        }
    }

    // Update the little marker numbers in all cells
    private void updateHelpersCb(Widget widget)
    {
        sudoku.updateHelpers();
    }

    void updateHelpers()
    {
        int j, k, m;

        // First we delete any entries that the user may have made
        for (j = 0; j < 9; j++)
            for (k = 0; k < 9; k++)
                gridCells_[j][k].clearHints();

        // Now go through all cells and find out, what we can not be
        for (j = 0; j < 81; j++)
        {
            bool[10] taken;
            // Find our destination cell
            int row = j / 9;
            int col = j % 9;
            SudokuCell dstCell = gridCells_[row][col];
            if (dstCell.value()) continue;
            // Find all values already taken in this row
            for (k = 0; k < 9; k++)
            {
                int v = gridCells_[row][k].value();
                if (v) taken[v] = true;
            }
            // Find all values already taken in this column
            for (k = 0; k < 9; k++)
            {
                int v = gridCells_[k][col].value();
                if (v) taken[v] = true;
            }
            // Now find all values already taken in this square
            int ro = (row / 3) * 3;
            int co = (col / 3) * 3;
            for (k = 0; k < 3; k++)
                for (m = 0; m < 3; m++)
                {
                    int v = gridCells_[ro + k][co + m].value();
                    if (v) taken[v] = true;
                }
            // transfer our findings to the markers
            for (m = 1; m <= 9; m++)
                if (!taken[m]) dstCell.setHint(m);
        }
        undoCheckpoint();
    }

    void clearHintsFor(int row, int col, int val)
    {
        int i, j;
        // clear row
        for (i = 0; i < 9; ++i) gridCells_[row][i].clearHint(val);
        // clear column
        for (i = 0; i < 9; ++i) gridCells_[i][col].clearHint(val);
        // clear block
        row = (row / 3) * 3;
        col = (col / 3) * 3;
        for (i = 0; i < 3; ++i)
            for (j = 0; j < 3; ++j)
                gridCells_[row + i][col + j].clearHint(val);
    }

    // Show the on-line help...
    private void helpCb(Widget widget)
    {
        if (helpDialog_ is null)
        {
            helpDialog_ = new HelpDialog();

            helpDialog_.value(
                "<HTML>\n" ~
                "<HEAD>\n" ~
                "<TITLE>Sudoku Help</TITLE>\n" ~
                "</HEAD>\n" ~
                "<BODY BGCOLOR='#ffffff'>\n" ~

                "<H2>About the Game</H2>\n" ~

                "<P>Sudoku (pronounced soo-dough-coo with the emphasis on the\n" ~
                "first syllable) is a simple number-based puzzle/game played on a\n" ~
                "9x9 grid that is divided into 3x3 subgrids. The goal is to enter\n" ~
                "a number from 1 to 9 in each cell so that each number appears\n" ~
                "only once in each column and row. In addition, each 3x3 subgrid\n" ~
                "may only contain one of each number.</P>\n" ~

                "<P>This version of the puzzle is copyright 2005-2010 by Michael R\n" ~
                "Sweet.</P>\n" ~

                "<P><B>Note:</B> The 'Hard' and 'Impossible' difficulty\n" ~
                "levels generate Sudoku puzzles with multiple possible solutions.\n" ~
                "While some purists insist that these cannot be called 'Sudoku'\n" ~
                "puzzles, the author (me) has personally solved many such puzzles\n" ~
                "in published/printed Sudoku books and finds them far more\n" ~
                "interesting than the simple single solution variety. If you don't\n" ~
                "like it, don't play with the difficulty set to 'High' or\n" ~
                "'Impossible'.</P>\n" ~

                "<H2>How to Play the Game</H2>\n" ~

                "<P>At the start of a new game, Sudoku fills in a random selection\n" ~
                "of cells for you - the number of cells depends on the difficulty\n" ~
                "level you use. Click in any of the empty cells or use the arrow\n" ~
                "keys to highlight individual cells and press a number from 1 to 9\n" ~
                "to fill in the cell. To clear a cell, press 0, Delete, or\n" ~
                "Backspace. When you have successfully completed all subgrids, the\n" ~
                "entire puzzle is highlighted in green until you start a new\n" ~
                "game.</P>\n" ~

                "<P>As you work to complete the puzzle, you can display possible\n" ~
                "solutions inside each cell by holding the Shift key and pressing\n" ~
                "each number in turn. Repeat the process to remove individual\n" ~
                "numbers, or press a number without the Shift key to replace them\n" ~
                "with the actual number to use.</P>\n" ~
                "</BODY>\n"
            );
        }

        helpDialog_.show();
    }

    // Load the game from saved preferences...
    void loadGame()
    {
        // Load the current values and state of each grid...
        foreach (ref row; gridValues_) row[] = 0;

        bool solved = true;

        for (int j = 0; j < 9; j++)
            for (int k = 0; k < 9; k++)
            {
                string name;
                int val;

                SudokuCell cell = gridCells_[j][k];

                name = format("value%d.%d", j, k);
                if (!prefs_.get(name, val, 0))
                {
                    j = 9;
                    gridValues_[0][0] = 0;
                    break;
                }

                gridValues_[j][k] = cast(char) val;

                name = format("state%d.%d", j, k);
                prefs_.get(name, val, 0);
                cell.value(val);

                name = format("readonly%d.%d", j, k);
                prefs_.get(name, val, 0);
                cell.readonly(val != 0);

                if (val) cell.color(gray);
                else
                {
                    cell.color(light3);
                    solved = false;
                }

                name = format("hint%d.%d", j, k);
                prefs_.get(name, val, 0);
                cell.setHintMap(val);
            }

        // If we didn't load any values or the last game was solved, then
        // create a new game automatically...
        if (solved || !gridValues_[0][0]) newGame(unpredictableSeed);
        else checkGame(false);
        clearUndo();
    }

    // Mute/unmute sound...
    private void muteCb(Widget widget)
    {
        if (sudoku.sound_ !is null)
        {
            destroy(sudoku.sound_);
            sudoku.sound_ = null;
            prefs_.set("mute_sound", 1);
        }
        else
        {
            sudoku.sound_ = new SudokuSound();
            prefs_.set("mute_sound", 0);
        }
    }

    // Create a new game...
    private void newCb(Widget widget)
    {
        if (sudoku.gridCells_[0][0].color() != green)
        {
            if (!choice("Are you sure you want to change the difficulty level and " ~
                           "discard the current game?", "Keep Current Game", "Start New Game",
                           null)) return;
        }
        sudoku.newGame(unpredictableSeed);
    }

    // Create a new game...
    void newGame(long seed)
    {
        int j, k, m, n, t, count;

        // Generate a new (valid) Sudoku grid...
        seed_ = seed;
        rndGen.seed(cast(uint) seed);

        foreach (ref row; gridValues_) row[] = 0;

        // Deliberate deviation from a faithful transliteration: FLTK's
        // own "start over" retry (`k = 9; j = -3;`) sits inside the `t`
        // loop, not the `k`/`j` loops it's meant to restart -- setting
        // those two variables doesn't exit anything immediately, so the
        // `t` loop keeps running with j=-3/k=9 for its own remaining
        // iterations, computing `m`/`n` outside [0,8] and indexing
        // grid_values_ out of bounds (undefined behavior in C++; a real,
        // bounds-checked `ArrayIndexError` crash in D). A labeled
        // `continue` is used instead, so "start over" actually jumps
        // back to the outer `j` loop immediately, matching the comment's
        // own clearly-stated intent.
        //
        // `foreach (ref row; gridValues_)`, not a plain `foreach (row;
        // ...)`: `gridValues_` is `char[9][9]`, a static array of static
        // arrays, and D's `foreach` binds a static-array *element* by
        // value unless the loop variable is declared `ref` -- without
        // `ref`, `row` would be a throwaway copy and `row[] = 0` would
        // clear nothing. The same applies to the matching resets inside
        // the `count == 20` "start over" branch below and in
        // `loadGame()`.
        outer: for (j = 0; j < 9; j += 3)
        {
            for (k = 0; k < 9; k += 3)
            {
                for (t = 1; t <= 9; t++)
                {
                    for (count = 0; count < 20; count++)
                    {
                        m = j + uniform(0, 3);
                        n = k + uniform(0, 3);
                        if (!gridValues_[m][n])
                        {
                            int mm;

                            for (mm = 0; mm < m; mm++)
                                if (gridValues_[mm][n] == t) break;

                            if (mm < m) continue;

                            int nn;

                            for (nn = 0; nn < n; nn++)
                                if (gridValues_[m][nn] == t) break;

                            if (nn < n) continue;

                            gridValues_[m][n] = cast(char) t;
                            break;
                        }
                    }

                    if (count == 20)
                    {
                        // Unable to find a valid puzzle so far, so start over...
                        foreach (ref row; gridValues_) row[] = 0;
                        j = -3;
                        continue outer;
                    }
                }
            }
        }

        // Start by making all cells editable
        SudokuCell cell;

        for (j = 0; j < 9; j++)
            for (k = 0; k < 9; k++)
            {
                cell = gridCells_[j][k];
                cell.value(0);
                cell.readonly(false);
                cell.color(light3);
                cell.clearHints();
            }

        // Show N cells...
        count = 11 * (5 - difficulty_);

        int[9] numbers;

        for (j = 0; j < 9; j++) numbers[j] = j + 1;

        while (count > 0)
        {
            for (j = 0; j < 20; j++)
            {
                k = uniform(0, 9);
                m = uniform(0, 9);
                t = numbers[k];
                numbers[k] = numbers[m];
                numbers[m] = t;
            }

            for (j = 0; count > 0 && j < 9; j++)
            {
                t = numbers[j];

                for (k = 0; count > 0 && k < 9; k++)
                {
                    cell = gridCells_[j][k];

                    if (gridValues_[j][k] == t && !cell.readonly())
                    {
                        cell.value(gridValues_[j][k]);
                        cell.readonly(true);
                        cell.color(gray);

                        count--;
                        break;
                    }
                }
            }
        }
        clearUndo();
    }

    // Return the next available value for a cell...
    int nextValue(SudokuCell c)
    {
        int j = 0, k = 0, m = 0, n = 0;

        for (j = 0; j < 9; j++)
        {
            for (k = 0; k < 9; k++)
                if (gridCells_[j][k] is c) break;

            if (k < 9) break;
        }

        if (j == 9) return 1;

        j -= j % 3;
        k -= k % 3;

        int[9] numbers;

        for (m = 0; m < 3; m++)
            for (n = 0; n < 3; n++)
            {
                SudokuCell cc = gridCells_[j + m][k + n];
                if (cc.value()) numbers[cc.value() - 1] = 1;
            }

        for (j = 0; j < 9; j++)
            if (!numbers[j]) return j + 1;

        return 1;
    }

    // Reset widget color to gray...
    private static void resetCb(Widget widget)
    {
        widget.color(light3);
        widget.redraw();

        (cast(Sudoku) widget.window()).checkGame(false);
    }

    // Resize the window...
    override void resize(int X, int Y, int W, int H)
    {
        // Resize the window...
        super.resize(X, Y, W, H);

        // Save the new window geometry...
        prefs_.set("x", X);
        prefs_.set("y", Y);
        prefs_.set("width", W);
        prefs_.set("height", H);
    }

    // Restart game from beginning...
    private void restartCb(Widget widget)
    {
        bool solved = true;

        for (int j = 0; j < 9; j++)
            for (int k = 0; k < 9; k++)
            {
                SudokuCell cell = sudoku.gridCells_[j][k];
                cell.clearHints();
                if (!cell.readonly())
                {
                    solved = false;
                    int v = cell.value();
                    cell.value(0);
                    cell.color(light3);
                    if (v && sudoku.sound_ !is null)
                        sudoku.sound_.play(cast(char)('A' + v - 1));
                }
            }

        if (solved)
            sudoku.newGame(sudoku.seed_);
        else
            sudoku.clearUndo();
    }

    // Save the current game state...
    void saveGame()
    {
        // Save the current values and state of each grid...
        for (int j = 0; j < 9; j++)
            for (int k = 0; k < 9; k++)
            {
                string name;
                SudokuCell cell = gridCells_[j][k];

                name = format("value%d.%d", j, k);
                prefs_.set(name, gridValues_[j][k]);

                name = format("state%d.%d", j, k);
                prefs_.set(name, cell.value());

                name = format("readonly%d.%d", j, k);
                prefs_.set(name, cell.readonly());

                for (int m = 0; m < 8; m++)
                {
                    name = format("hint%d.%d", j, k);
                    prefs_.set(name, cell.getHintMap());
                }
            }
    }

    void saveState(ref GameState s)
    {
        for (int j = 0; j < 9; j++)
            for (int k = 0; k < 9; k++)
                s[j * 9 + k] = gridCells_[j][k].state();
    }

    void loadState(ref GameState s)
    {
        for (int j = 0; j < 9; j++)
            for (int k = 0; k < 9; k++)
                gridCells_[j][k].state(s[j * 9 + k]);
    }

    void undo()
    {
        if (undoHead_ != undoTail_)
        {
            undoHead_ = (undoHead_ - 1) & 63;
            loadState(undoStack[undoHead_]);
            redraw();
        }
        else
        {
            fl_beep(Beep.error);
        }
    }

    void redo()
    {
        if (undoHead_ != redoHead_)
        {
            undoHead_ = (undoHead_ + 1) & 63;
            loadState(undoStack[undoHead_]);
            redraw();
        }
        else
        {
            fl_beep(Beep.error);
        }
    }

    void clearUndo()
    {
        undoHead_ = undoTail_ = redoHead_ = 0;
        saveState(undoStack[undoHead_]);
    }

    void undoCheckpoint()
    {
        if (undoHead_ == redoHead_)
            redoHead_ = (redoHead_ + 1) & 63;
        undoHead_ = (undoHead_ + 1) & 63;
        if (undoHead_ == undoTail_)
            undoTail_ = (undoTail_ + 1) & 63;
        saveState(undoStack[undoHead_]);
    }

    // Set title of window...
    private void setTitle()
    {
        static immutable string[4] titles = [
            "Sudoku - Easy",
            "Sudoku - Medium",
            "Sudoku - Hard",
            "Sudoku - Impossible"
        ];

        label(titles[difficulty_]);
    }

    // Solve the puzzle...
    private void solveCb(Widget widget)
    {
        sudoku.solveGame();
    }

    // Solve the puzzle...
    void solveGame()
    {
        int j, k;

        for (j = 0; j < 9; j++)
        {
            for (k = 0; k < 9; k++)
            {
                SudokuCell cell = gridCells_[j][k];

                cell.value(gridValues_[j][k]);
                cell.readonly(true);
                cell.color(gray);
            }

            if (sound_ !is null)
                sound_.play(cast(char)('A' + gridCells_[j][8].value() - 1));
        }
        undoCheckpoint();
    }
}

Sudoku sudoku;

private void undoCb(Widget widget) { sudoku.undo(); }
private void redoCb(Widget widget) { sudoku.redo(); }

// XBM bitmap data for the window icon lives in test/pixmaps/sudoku.xbm
// FLTK; not transliterated here (asset data, not FLTK API surface).
immutable(ubyte)[] sudokuBits;
enum int sudokuWidth = 24;
enum int sudokuHeight = 24;

// Main entry for game...
void main(string[] args)
{
    auto s = new Sudoku();
    sudoku = s;

    // Show the game...
    s.show();

    // Load the previous game...
    s.loadGame();

    // Run until the user quits...
    fl.run();
}
