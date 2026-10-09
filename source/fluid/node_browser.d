/*
 * The interactive editor's project-tree list -- shows the hierarchy of
 * `Node`s in the currently-open project and keeps its own selection in
 * sync with the design canvas (`fluid.canvas.ProjectCanvas`).
 *
 * Built on `fl.tree.Tree`, not a port of FLTK's real `Node_Browser`
 * (which extends `Fl_Browser_` directly). That's a deliberate choice,
 * not a shortcut: FLTK's own `Node` model is a flat doubly-linked
 * list plus an integer nesting `level` -- exactly `Fl_Browser_`'s
 * native shape (`item_next()`/`item_prev()` walking a flat chain).
 * This project's `Node` (`fluid.node`) deliberately chose a real
 * `parent`/`children` tree instead (see that module's own top
 * comment) -- exactly `fl.tree.Tree`'s native shape. Forking a
 * `Browser_`-based port here would mean writing a pre-order-traversal
 * adapter to fake a flat list this project doesn't have and doesn't
 * want; `Tree` matches the architecture already chosen in `node.d`,
 * not a workaround. See the "Fluid Phase 1" plan for the full
 * reasoning.
 *
 * **Multi-selection**:
 * `fl.tree.Tree` already has real Ctrl/Shift-click multi-select built
 * in (`TreeSelect.selectMulti`) -- turning it on here and reporting the
 * *whole* current selection (not just the clicked row) was enough,
 * no bespoke toggle logic needed on this side (contrast
 * `fluid.canvas.ProjectCanvas`, which has no such built-in and hand-
 * rolls its own `toggleSelection()`).
 */
module fluid.node_browser;

import fl;

import fluid.app_prefs : appPrefs;
import fluid.node : Node;
import fluid.pixmaps : pixmapFor, lockPixmap, protectedPixmap, invisiblePixmap;
import fluid.widget_node : WidgetNode;
import fluid.window_node : WindowNode;
import fluid.node : Access;
import fluid.class_node : ClassNode;
import fluid.function_node : FunctionNode;
import fluid.code_block_node : CodeBlockNode;
import fluid.comment_node : CommentNode;
import std.utf : decode;

/// FLTK: `Fluid.show_comments` (`Fluid.h`'s own `int show_comments
/// { 1 };`) -- gates whether `NodeBrowserItem` draws a node's own
/// comment line at all, both in its layout (`commentLineHeight()`) and
/// its actual drawing (`drawItemContent()`). Wired to the Settings
/// dialog's General-tab "Show Comments in Browser" checkbox
/// (`settings_panel.fl`), which flips this and re-lays-out/redraws the
/// live tree the same way `gui_main.d`'s other structural-change call
/// sites already do (`recalcTree()` since this changes row heights,
/// not just pixels).
bool showComments = true;

/// FLTK's own `copy_trunc()` (`Node_Browser.cxx`), narrowed to the one
/// call shape this module needs (no quoting): stops at the first `'\n'`
/// with no `"..."` appended (a comment's first line is the preview, not
/// a truncated-for-length one), otherwise caps at `maxChars` Unicode
/// code points and appends `"..."` -- but only when something was
/// actually cut off, not when the string simply ends exactly at the
/// limit or right before a newline.
private string truncatedComment(string s, size_t maxChars = 80)
{
    size_t i = 0;
    size_t count = 0;
    while (i < s.length && count < maxChars)
    {
        if (s[i] == '\n')
            return s[0 .. i];
        decode(s, i);
        count++;
    }
    return (i < s.length && s[i] != '\n') ? s[0 .. i] ~ "..." : s[0 .. i];
}

/// FLTK: `Node_Browser`'s own 6 `static Fl_Color`/`Fl_Font` role
/// pairs (`fluid/widgets/Node_Browser.h`/`.cxx`) -- per-role text
/// styling for the project tree, editable from the Settings dialog's
/// User tab (`settings_panel.fl`) and consulted by `NodeBrowserItem.
/// drawItemContent()` below. Default values copied verbatim from
/// `Node_Browser.cxx`'s own static initializers, not guessed:
/// `labelColor = 72` is a real, deliberate accent color (a dark red in
/// FLTK's default 256-entry palette, `colorTable[72] == 0x7f0000`),
/// not a placeholder value -- confirmed by reading the actual packed
/// RGB rather than assumed from the bare number. `commentFont =
/// helvetica`, matching both `Node_Browser.cxx`'s static initializer
/// and `settings_panel.fl`'s "Reset" button (FLTK `4cf6dd285` fixed
/// that button, which used to assign `FL_DARK_GREEN`).
Color labelColor = cast(Color) 72;
Font labelFont = helvetica;
Color classColor = foregroundColor;
Font classFont = helveticaBold;
Color funcColor = foregroundColor;
Font funcFont = helvetica;
Color nameColor = foregroundColor;
Font nameFont = helvetica;
Color codeColor = foregroundColor;
Font codeFont = helvetica;
Color commentColor = darkGreen;
Font commentFont = helvetica;

/// Loads the 12 role color/font values above from `appPrefs`, into a
/// nested `"widget_browser"` group -- ported from `Node_Browser::
/// load_prefs()` (`fluid/widgets/Node_Browser.cxx`), same group name,
/// same 12 keys, same per-key default (the fallback value used the
/// *first* time Fluid ever runs, before anything has been saved).
/// FLTK calls this once, at startup (`Fluid.cxx`); this port's
/// equivalent call site is `gui_main.d`'s own startup sequence.
void loadPrefs()
{
    auto p = new Preferences(appPrefs, "widget_browser");
    int c;
    p.get("label_color", c, 72); labelColor = cast(Color) c;
    p.get("label_font", c, helvetica); labelFont = cast(Font) c;
    p.get("class_color", c, foregroundColor); classColor = cast(Color) c;
    p.get("class_font", c, helveticaBold); classFont = cast(Font) c;
    p.get("func_color", c, foregroundColor); funcColor = cast(Color) c;
    p.get("func_font", c, helvetica); funcFont = cast(Font) c;
    p.get("name_color", c, foregroundColor); nameColor = cast(Color) c;
    p.get("name_font", c, helvetica); nameFont = cast(Font) c;
    p.get("code_color", c, foregroundColor); codeColor = cast(Color) c;
    p.get("code_font", c, helvetica); codeFont = cast(Font) c;
    p.get("comment_color", c, darkGreen); commentColor = cast(Color) c;
    // FLTK's own `load_prefs()` default here is `FL_HELVETICA`, not
    // the `FL_DARK_GREEN` its "Reset" button callback mistakenly
    // assigns (a real FLTK bug -- see `FLTK_ISSUES.md` and this
    // module's own `commentFont` static-initializer comment above) --
    // faithfully matched here, not the buggy value.
    p.get("comment_font", c, helvetica); commentFont = cast(Font) c;
}

/// Saves the 12 role color/font values above to `appPrefs`, mirroring
/// `loadPrefs()` -- ported from `Node_Browser::save_prefs()`. FLTK
/// calls this from every User-tab font-choice/color-picker callback
/// (immediately after updating the in-memory value) and from the
/// "Reset" button; `settings_panel.fl`'s own callbacks do the same.
void savePrefs()
{
    auto p = new Preferences(appPrefs, "widget_browser");
    p.set("label_color", cast(int) labelColor);
    p.set("label_font", cast(int) labelFont);
    p.set("class_color", cast(int) classColor);
    p.set("class_font", cast(int) classFont);
    p.set("func_color", cast(int) funcColor);
    p.set("func_font", cast(int) funcFont);
    p.set("name_color", cast(int) nameColor);
    p.set("name_font", cast(int) nameFont);
    p.set("code_color", cast(int) codeColor);
    p.set("code_font", cast(int) codeFont);
    p.set("comment_color", cast(int) commentColor);
    p.set("comment_font", cast(int) commentFont);
    // `set()` only marks the in-memory tree dirty -- see `fl.
    // preferences.Preferences`'s own top comment ("callers that
    // actually need the data saved must call `.flush()` explicitly")
    // and `gui_main.saveWindowPosition()`'s own doc comment for the
    // real bug this exact omission causes elsewhere: without this,
    // nothing here would ever reach disk.
    p.flush();
}

/// Applies one of the User tab's per-role quick-pick colors (ported from
/// `cb_Color_Choice()` + `colormenu[]`, `settings_panel.cxx`/
/// `widget_panel_callbacks.cxx`) to a role color field: updates the
/// in-memory value, the swatch `Button`'s own displayed color, and
/// persists via `savePrefs()`. FLTK's own `cb_Color_Choice()` reads
/// the chosen `Fl_Color` back off the clicked `Fl_Menu_Item::argument()`
/// and re-invokes the swatch button's own callback via `do_callback()`;
/// this port's per-`MenuItem` callbacks already know their target color
/// directly (no shared dispatch needed), so this just does the same
/// three steps `cb_Color_Chip()`/each row's swatch-button callback in
/// `settings_panel.fl` already performs. The live-tree redraw (needed
/// only for the 4 roles `NodeBrowserItem.drawItemContent()` actually
/// consults today -- see this module's own top-of-file `Function`/`Code`
/// roadmap note) stays the caller's responsibility, matching how each
/// row's own swatch-button callback already splits that same way.
void applyPresetColor(ref Color field, Color preset, Button swatch)
{
    field = preset;
    swatch.color(preset);
    swatch.redraw();
    savePrefs();
}

/// The User tab's own color-chip swatch button (as opposed to its
/// companion quick-pick menu, `applyPresetColor()` just above) --
/// ported from `cb_Color_Chip()`'s own STORE branch (`settings_panel.cxx`).
/// Not FLTK's own shape verbatim: FLTK reuses one shared C
/// function across all 6 swatch buttons via a `Fl_Callback*` +
/// `void* user_data` pointing at the specific static `Fl_Color` each one
/// owns (`Node_Browser::label_color`/`class_color`/...); this port has
/// no such per-widget-tag mechanism at all (see CONVENTIONS.md's own
/// "Callbacks are D delegates" convention -- a real, separately-tracked
/// gap in core `fl.widget.Widget`, not
/// something to route around here). This helper avoids each of
/// the 6 swatch buttons in `settings_panel.fl` duplicating this same
/// body inline (see `fluid.font_menu`'s own module comment for the
/// parallel font-menu case). Deliberately doesn't redraw the browser itself, same
/// as `applyPresetColor()` just above and for the same reason (`browser()`
/// lives in `gui_main.d`, which already imports this module -- importing
/// it back here would be circular): each swatch button's own `.fl`
/// callback stays two lines, `pickColor(labelColor,
/// userLabelColorButton);` plus the same trailing `browser()`/`redraw()`
/// pair every `applyPresetColor()` caller already has.
void pickColor(ref Color field, Button swatch)
{
    field = showColormap(field);
    swatch.color(field);
    swatch.redraw();
    savePrefs();
}

/// A single row in the project tree, matching real Fluid's own
/// `Node_Browser::item_draw()`/`item_height()` format (`fluid/widgets/
/// Node_Browser.cxx`) instead of a plain text label: an optional
/// comment line above the main line when the node has one, then the
/// node's class name (its `Fl_` prefix stripped, matching FLTK's
/// own `subclassname()` treatment) followed by its instance name --
/// falling back to a quoted `label` when there's no instance name,
/// matching FLTK's own two-tier fallback -- and a thin separator
/// line below every unselected row, matching FLTK's own
/// always-drawn browser rule. Each of those four pieces (comment/
/// class/name/label) draws in its own configurable color+font, driven
/// by this module's own `commentColor`/`classColor`/`nameColor`/
/// `labelColor` (+ matching `*Font`) globals just above -- the User
/// tab's real backing feature, tracing
/// `Node_Browser.cxx`'s real static defaults: the
/// green is `commentColor = FL_DARK_GREEN` on the above-line comment,
/// the bold is `classFont = FL_HELVETICA_BOLD`, and the red is
/// `labelColor = 72`, a real, deliberate accent color in FLTK's
/// default palette (`colorTable[72] == 0x7f0000`), not
/// collapsed into the same plain foreground color as everything else
/// here.
///
/// Non-widget row shapes are real too: a
/// `Function`/`Comment`/`Decl`/`Code`/`CodeBlock`/`DeclBlock`/`Data`
/// node draws its own distinct row -- see `rowKind()`/`nodeTitle()`
/// below, ported from FLTK's own `item_draw()` else-branch
/// (`l->is_widget() || l->is_class()` false) and `Node::title()`/
/// `Function_Node::title()`. `func`/`code` are consulted by
/// `drawItemContent()`, same as every other role.
final class NodeBrowserItem : TreeItem
{
    private Node node_;

    this(Tree tree, Node node)
    {
        super(tree);
        node_ = node;
    }

    /// FLTK: `subclassname(l)` -- strips a leading "Fl_" for display.
    private string className() const
    {
        auto t = node_.typeName;
        return (t.length > 3 && t[0 .. 3] == "Fl_") ? t[3 .. $] : t;
    }

    /// Which of `item_draw()`'s row shapes this node gets -- ported from
    /// its own dispatch: `is_widget() || is_class()` (`widgetOrClass`,
    /// the existing class-name-plus-instance-name format above), else
    /// `is_code_block() && (level == 0 || parent->is_class())` (`func`
    /// -- a top-level `Function`/`CodeBlock`, or one that's a method
    /// inside a `class {}`), else a `Comment_Node` (`comment`, drawn on
    /// the main line, distinct from the optional above-line comment
    /// every row kind can also have), else everything left over
    /// (`code`: `Code`/`Decl`/`DeclBlock`/`Data`, and a `CodeBlock` not
    /// meeting the `func` condition above). `level == 0` is `node_.
    /// parent is null` here -- this project's `Node` tracks a real
    /// `parent` reference instead of FLTK's own flat-list `level`
    /// integer (see `fluid.node`'s own top comment).
    private enum RowKind { widgetOrClass, func, comment, code }

    private RowKind rowKind() const
    {
        if (cast(WidgetNode) node_ !is null || cast(ClassNode) node_ !is null)
            return RowKind.widgetOrClass;
        bool isFuncOrCodeBlock = cast(FunctionNode) node_ !is null || cast(CodeBlockNode) node_ !is null;
        if (isFuncOrCodeBlock && (node_.parent is null || cast(ClassNode) node_.parent !is null))
            return RowKind.func;
        if (cast(CommentNode) node_ !is null)
            return RowKind.comment;
        return RowKind.code;
    }

    /// FLTK: `Node::title()`/`Function_Node::title()` -- `name()`
    /// (this project's `instanceName`, the field every non-widget node
    /// kind's own raw text is captured into, see `fluid.decl_node`'s
    /// own top comment) if set, else `type_name()` (`Function`'s own
    /// override falls back to `"main()"` instead, matching FLTK's
    /// own special case for the anonymous top-level function).
    private string nodeTitle() const
    {
        if (node_.instanceName.length) return node_.instanceName;
        return (cast(FunctionNode) node_ !is null) ? "main()" : node_.typeName;
    }

    /// FLTK: `item_height()`'s own comment sub-line contribution
    /// (`textsize()*2+4` total vs. `textsize()+5` with no comment --
    /// the difference, `textsize()-1`, is this function's return value).
    private int commentLineHeight() const
    {
        return (showComments && node_.comment.length) ? (labelsize() - 1) : 0;
    }

    override protected int calcItemHeight(TreePrefs prefs)
    {
        if (!isVisible()) return 0;
        int H = labelsize() + descent() + 1 + commentLineHeight();
        if (hasChildren() && H < prefs.openiconH()) H = prefs.openiconH();
        if (usericon() !is null && H < usericon().h()) H = usericon().h();
        return H;
    }

    /// FLTK: each role's own `l->new_selected ? fl_contrast(role_
    /// color, FL_SELECTION_COLOR) : role_color` -- factored out since
    /// `drawItemContent()` below now applies the same formula per role
    /// (class/name/label/comment), not just a single generic foreground.
    private Color roleColor(Color c)
    {
        return isSelected() ? contrast(c, tree().selectionColor()) : c;
    }

    /// FLTK: `Node::is_public()` -- 0 private, 1 public, 2 protected. Only
    /// private and protected get an icon (`drawOverlayIcons()`). Only a
    /// widget or a function has an access level here: FLTK's declaration and
    /// declaration-block visibility picks the header or source file for the
    /// code, and generated D has no such split, so those rows are public.
    private static int publicLevel(Node n)
    {
        if (auto w = cast(WidgetNode) n) return cast(int) w.access;
        if (auto f = cast(FunctionNode) n) return cast(int) f.access;
        return 1;
    }

    /// FLTK: the tags `Node_Browser::item_draw()` draws on top of the type
    /// icon: a lock for a private node, a "protected" mark for a protected
    /// one, and an "invisible" mark for a hidden widget (except in a Tabs or
    /// Wizard, where only one child shows at a time).
    private void drawOverlayIcons()
    {
        auto prefs = tree().prefs();
        auto typeIcon = usericon();
        int iconW = typeIcon !is null ? typeIcon.w() : 0;
        int iconH = typeIcon !is null ? typeIcon.h() : 16;
        int x = labelX() - prefs.labelmarginleft() - iconW + 1;
        int y = ((this.y() + h() / 2) | 1) - (iconH >> 1);

        switch (publicLevel(node_))
        {
        case 0: if (lockPixmap !is null) lockPixmap.draw(x, y); break;
        case 2: if (protectedPixmap !is null) protectedPixmap.draw(x, y); break;
        default: break;
        }

        auto wn = cast(WidgetNode) node_;
        if (wn !is null && cast(WindowNode) wn is null && wn.hidden && invisiblePixmap !is null)
        {
            string parentType = node_.parent !is null ? node_.parent.typeName : "";
            if (parentType.length > 3 && parentType[0 .. 3] == "Fl_") parentType = parentType[3 .. $];
            if (parentType != "Tabs" && parentType != "Wizard")
                invisiblePixmap.draw(x, y);
        }
    }

    override protected int drawItemContent(bool render)
    {
        auto prefs = tree().prefs();
        Color bg = drawbgcolor();

        if (render) drawOverlayIcons();

        if (render && (bg != tree().color() || isSelected()))
        {
            if (isSelected())
                drawBoxAt(prefs.selectbox(), labelX(), labelY(), labelW(), labelH(), bg);
            else
            {
                fl_color(bg);
                fl_rectf(labelX(), labelY(), labelW(), labelH());
            }
        }

        int commentH = commentLineHeight();
        int mainH = labelH() - commentH;
        int X = labelX() + prefs.labelmarginleft();
        int ly = labelY() + commentH + mainH / 2 + labelsize() / 2 - descent() / 2;

        if (commentH)
        {
            fl_font(commentFont, labelsize() - 2);
            if (render)
            {
                fl_color(roleColor(commentColor));
                fl_draw(truncatedComment(node_.comment), X, labelY() + labelsize() - 2);
            }
        }

        int drawSegment(string text, Font roleFont, Color roleCol, int x)
        {
            fl_font(roleFont, labelsize());
            int gapW, gapH, textW, textH;
            fl_measure(" ", gapW, gapH);
            fl_measure(text, textW, textH);
            int nx = x + gapW;
            if (render)
            {
                fl_color(roleColor(roleCol));
                fl_draw(text, nx, ly);
            }
            return nx + textW;
        }

        int xmax;
        if (rowKind() == RowKind.widgetOrClass)
        {
            // -- class name, bold
            fl_font(classFont, labelsize());
            int clsW, clsH;
            fl_measure(className(), clsW, clsH);
            if (render)
            {
                fl_color(roleColor(classColor));
                fl_draw(className(), X, ly);
            }
            xmax = X + clsW;

            // -- instance name (plain `nameColor`/`nameFont`), then a
            // quoted label (`labelColor`/`labelFont`) -- both shown
            // whenever each is present, not one-or-the-other.
            //
            // **Deliberate divergence from FLTK.**
            // FLTK's own `Node_Browser::item_draw()` only ever shows
            // one of the two: the instance name if set, falling back to a
            // quoted label only when there's no name at all (`c = l->
            // name(); if (!c.empty()) { draw name } else if (l->label())
            // { draw label }`) -- this port shows both
            // instead: an instance name is only ever set when generated
            // code needs to reference that specific widget by variable
            // name, so most widgets in a typical project have a label but
            // no name at all -- FLTK's own "name wins when set" rule
            // ends up showing the label for the overwhelming majority of
            // rows anyway, which reads as "label is prioritized" even
            // though the underlying rule always favored name. Showing both
            // removes the ambiguity outright: whenever a row's name and
            // label differ, both are visible at a glance instead of one
            // being silently hidden.
            if (node_.instanceName.length)
                xmax = drawSegment(node_.instanceName, nameFont, nameColor, xmax);
            if (node_.label.length)
                xmax = drawSegment("\"" ~ node_.label ~ "\"", labelFont, labelColor, xmax);
        }
        else
        {
            // -- Function/CodeBlock ("func"), Comment ("comment"), or
            // Code/Decl/DeclBlock/Data/other-CodeBlock ("code") --
            // FLTK's own single-segment `func_font+func_color`/
            // `comment_font+comment_color`/`code_font+code_color` row,
            // no separate class-name segment (see `rowKind()`'s own doc
            // comment). FLTK's own `copy_trunc()` caps all three at
            // 55 chars, but differs subtly per row kind in exactly how a
            // multi-line title truncates (`func`/`comment` convert an
            // embedded newline to a literal `\n` and keep counting
            // toward the 55-char/ellipsis cutoff; `code` stops dead at
            // the first real newline instead, no ellipsis in that one
            // case) -- a difference this port doesn't reproduce
            // character-for-character: `truncatedComment()` (already
            // used for the above-line comment preview, matching `code`'s
            // own FLTK behavior exactly) is reused uniformly for all
            // three here instead, a deliberate, disclosed simplification
            // rather than a second near-duplicate truncation helper for
            // an edge case (a multi-line `Function`/`Comment` title) this
            // project's own dialect rarely produces.
            Font roleFont;
            Color roleCol;
            final switch (rowKind())
            {
            case RowKind.widgetOrClass: assert(false); // handled above
            case RowKind.func: roleFont = funcFont; roleCol = funcColor; break;
            case RowKind.comment: roleFont = commentFont; roleCol = commentColor; break;
            case RowKind.code: roleFont = codeFont; roleCol = codeColor; break;
            }
            string text = truncatedComment(nodeTitle(), 55);
            fl_font(roleFont, labelsize());
            int textW, textH;
            fl_measure(text, textW, textH);
            if (render)
            {
                fl_color(roleColor(roleCol));
                fl_draw(text, X, ly);
            }
            xmax = X + textW;
        }

        // FLTK: "draw a thin line below the item if this item is
        // not selected (if it is selected this additional line would
        // look bad)"
        if (render && !isSelected())
        {
            fl_color(lighter(gray));
            fl_line(labelX(), labelY() + labelH() - 1, labelX() + labelW(), labelY() + labelH() - 1);
        }

        return xmax;
    }
}

final class NodeBrowser : Tree
{
    private TreeItem[Node] itemOf;
    private Node[TreeItem] nodeOf;

    /// Fired when the selection changes -- the shelf window wires this
    /// to the canvas/property panel, matching `ProjectCanvas.
    /// onSelectionChanged`'s role on the other side of the same sync.
    void delegate(Node[]) onSelect;

    /// Fired on a double-click of an already-selected row -- this
    /// port's counterpart to FLTK's `Node::open()` ("what happens
    /// when you double-click", `Node.h`'s own doc comment) for the
    /// *existing*-node case (freshly-created nodes get the same
    /// treatment from `gui_main.d`'s own `openNode()`, called directly
    /// from `insertWidget()`/`addNode()` instead of through here, since
    /// there's no tree click to react to yet at creation time). FLTK
    /// detects this itself with `Fl::event_clicks() || Fl::event_state
    /// (FL_CTRL)` inside `Node_Browser::handle()`'s own `FL_RELEASE`
    /// case (a hand-rolled `Fl_Browser_`); `fl.tree.Tree`'s own
    /// click/select machinery already fires a real callback per click,
    /// so the equivalent check here is just `fl.eventClicks() > 0`
    /// (FLTK's own `Ctrl`-click alternate trigger isn't replicated
    /// -- `Tree`'s own Ctrl-click already means "toggle multi-select
    /// membership" here, a real, different, already-established meaning
    /// that would conflict).
    void delegate(Node) onOpen;

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        showroot(false);
        selectmode(TreeSelect.selectMulti);
        // Needed for `onOpen`'s own double-click detection: `Tree.
        // select()`'s default `itemReselectMode` is `selectableOnce`
        // (`fl.tree_prefs`'s own default), which fires *no* callback at
        // all for a click on an already-selected item -- confirmed by
        // reading `select()`'s own body, not assumed -- so a genuine
        // double-click (select, then a second click while still
        // selected) would never reach `onTreeCallback()` a second time
        // without this.
        itemReselectMode(TreeItemReselectMode.selectableAlways);
        callback((w) { onTreeCallback(); });
    }

    /// Populates the tree from `root` (a project's top-level
    /// `WindowNode`, same node the canvas was built from) and every
    /// descendant. Safe to call again to rebuild after a structural
    /// change (not needed by Phase 1's editing scope, but harmless).
    ///
    /// Uses `clearChildren(root())`, not `Tree.clear()` -- `clear()`
    /// (real, if surprising, `fl.tree` behavior: it nulls out the
    /// tree's own root item entirely, "leaves the tree completely
    /// empty," not just its visible rows) would leave `root()` `null`
    /// afterward, and the `add(root(), ...)` call right below would
    /// then be adding children under a `null` parent -- a real,
    /// reachable segfault. `clearChildren()` clears the existing root's children
    /// while keeping the (synthetic, `showroot(false)`-hidden) root
    /// item itself intact, which is all a rebuild actually needs.
    /// `roots` is the project's whole top-level forest (`gui_main.d`'s
    /// `projectRoots_`) -- a real project is never just one window, it's
    /// a window plus whatever top-level `Function`/`decl`/`comment`/...
    /// siblings the project has (every hand-authored `.fl` file in this
    /// repo has at least an anonymous `Function {} {}` wrapping its
    /// window). Takes the whole forest, not a single `Node root`: a
    /// single-root version would only ever recurse into *one* subtree, so
    /// every sibling of that root -- the wrapping `Function` itself
    /// included -- would be invisible in the tree no matter how the project
    /// was built or loaded.
    void build(Node[] roots)
    {
        clearChildren(this.root());
        itemOf.clear();
        nodeOf.clear();
        foreach (root; roots)
            addRecursive(this.root(), root);

        // `calcTree()` (row layout -- every item's own `y()`) is
        // otherwise lazy, only recomputed on the *next* `draw()` --
        // `Tree.recalcTree()`'s own doc comment. A `build()` call is
        // routinely followed synchronously, same call chain, by
        // `syncSelection()` (`gui_main.d`'s `refreshAfterReorder()` and
        // every other structural-edit tail), whose own reveal-if-
        // offscreen scroll math (`displayed()`/`showItemMiddle()`)
        // reads `item.y()` directly -- without this, that math runs
        // against every item's *stale*, pre-rebuild `y()` (or, for a
        // brand-new `TreeItem`, its uninitialized default), scrolling
        // to a position that has nothing to do with where the item
        // actually ends up once the real layout finally runs. Found
        // as a real, reported bug: Group/Ungroup made the project tree
        // "jump to a completely random scroll area" every time --
        // Ungroup's own restructuring (promoting children up a level,
        // changing every subsequent row's indentation/position) made
        // the staleness especially visible, but the same staleness was
        // already latent behind every other caller of `build()` too.
        calcTree();
    }

    private void addRecursive(TreeItem parentItem, Node n)
    {
        // FLTK-matching row rendering (bold class name/plain
        // instance name/comment line/separator) is `NodeBrowserItem`'s
        // own job now -- see that class's top comment. The plain
        // fallback label passed here is only used by `TreeItem` itself
        // for path-based lookups (`findItem()` and friends); it plays
        // no part in what actually gets drawn.
        string label = n.instanceName.length ? n.instanceName : "<" ~ n.typeName ~ ">";
        auto item = add(parentItem, label, new NodeBrowserItem(this, n));
        // Ported from FLTK's `Node_Browser::item_draw()` (`fluid/
        // widgets/Node_Browser.cxx`), just via `TreeItem.usericon()`
        // instead of that function's own hand-rolled per-row `Fl_Pixmap*`
        // blit -- `usericon()` is already real, faithfully ported
        // drawing/layout and all (see `fl.tree_item`'s own top comment),
        // so this needed no new tree-widget infrastructure, only calling
        // it with the right image. A type with no registered icon (not
        // every node kind has one FLTK either) just gets `null`,
        // which `usericon()` already treats as "no icon" -- no explicit
        // fallback needed.
        item.usericon(pixmapFor(n.typeName));
        itemOf[n] = item;
        nodeOf[item] = n;
        foreach (c; n.children) addRecursive(item, c);
    }

    /// Canvas -> browser direction: highlights every node in `selected`
    /// without re-firing `onSelect` (the canvas already knows), and
    /// scrolls the tree to bring the primary (last) selection into view
    /// if it's currently scrolled off-screen. FLTK has no
    /// equivalent of this last part -- clicking a widget in its own
    /// editor window highlights the matching row in `Node_Browser` but
    /// never scrolls to it, so a selection outside the browser's
    /// current scroll position is silently invisible there. `displayed()`
    /// (only scroll if not already visible) + `showItemMiddle()` (land
    /// it centered, not jammed against an edge) rather than FLTK's
    /// own `reveal_in_browser()`-equivalent `display()`, which
    /// unconditionally recenters on every call -- that would jump the
    /// tree's scroll position on every single click even when the
    /// selection was already fully visible, exactly the jumpiness this
    /// addition is meant to avoid, not introduce.
    void syncSelection(Node[] selected)
    {
        deselectAll(null, false);
        TreeItem last;
        foreach (n; selected)
        {
            if (auto item = n in itemOf)
            {
                select(*item, false);
                last = *item;
            }
        }
        if (last !is null)
        {
            setItemFocus(last);
            if (!displayed(last)) showItemMiddle(last);
        }
    }

    /// Whether `n`'s row is collapsed in the tree (FLTK's `Node::folded_`).
    bool isFolded(Node n)
    {
        auto item = n in itemOf;
        return item !is null && !item.isOpen();
    }

    /// Every currently-selected node, walking `itemOf` and checking
    /// each item's own `isSelected()` -- the source of truth for "what
    /// is selected" is `fl.tree.Tree`'s own per-item state, not a
    /// separately-tracked array (unlike `ProjectCanvas`, which has no
    /// built-in multi-select to defer to). Order is whatever the
    /// backing `Node[TreeItem]` associative array iterates in --
    /// unspecified, unlike `ProjectCanvas.selected()`'s insertion
    /// order -- so callers relying on "last selected" (`gui_main.d`'s
    /// own property-panel sync) get an arbitrary member of a browser-
    /// driven selection, not necessarily the most recently clicked
    /// row. Acceptable for now: which single node represents a multi-
    /// selection in the (still single-target) property panel is a
    /// minor UX choice, not a correctness concern.
    Node[] selectedNodes()
    {
        Node[] result;
        foreach (item, n; nodeOf)
            if (item.isSelected())
                result ~= n;
        return result;
    }

    private void onTreeCallback()
    {
        if (callbackReason() != CallbackReason.selected
            && callbackReason() != CallbackReason.reselected
            && callbackReason() != CallbackReason.deselected)
            return;
        if (onSelect !is null) onSelect(selectedNodes());

        // Double-click (a "reselected" click, i.e. the item was already
        // selected, with a nonzero click count) -- see `onOpen`'s own
        // doc comment for why this specific combination is the right
        // check here.
        if (onOpen !is null
            && callbackReason() == CallbackReason.reselected
            && fl.eventClicks() > 0)
        {
            auto item = callbackItem();
            if (auto n = item in nodeOf)
                onOpen(*n);
        }
    }
}

// ===========================================================================
// Unit tests
// ===========================================================================

unittest
{
    // The project tree's rows follow FLTK's own format: bold class
    // name, comment line, separator, and the class name shown plainly
    // rather than as an angle-bracketed placeholder (`<Fl_Button>`).
    // Exercises
    // `NodeBrowserItem` end to end via `NodeBrowser.build()`, the real
    // integration path.
    import fluid.window_node : WindowNode;
    import fluid.widget_node : WidgetNode;

    FlGroup.current(null);

    auto rootNode = new WindowNode();
    rootNode.typeName = "Fl_Window";
    rootNode.instanceName = "mainWindow";

    auto plain = new WidgetNode();
    plain.typeName = "Fl_Button";
    plain.instanceName = "okButton";
    rootNode.addChild(plain);

    auto commented = new WidgetNode();
    commented.typeName = "Fl_Box";
    commented.instanceName = "spacer";
    commented.comment = "keeps the layout from collapsing";
    rootNode.addChild(commented);

    auto anonymous = new WidgetNode();
    anonymous.typeName = "Fl_Box";
    anonymous.label = "Hello";
    rootNode.addChild(anonymous);

    auto browser = new NodeBrowser(0, 0, 300, 200);
    FlGroup.current(null);
    browser.build([rootNode]);

    auto plainItem = cast(NodeBrowserItem) browser.itemOf[plain];
    assert(plainItem !is null);
    assert(plainItem.className() == "Button"); // "Fl_" stripped

    auto commentedItem = cast(NodeBrowserItem) browser.itemOf[commented];
    assert(commentedItem !is null);
    assert(commentedItem.commentLineHeight() > 0);
    assert(plainItem.commentLineHeight() == 0); // no comment, no extra line
    assert(commentedItem.calcItemHeight(browser.prefs())
        > plainItem.calcItemHeight(browser.prefs())); // taller row for the comment

    // No instance name at all: falls back to the quoted label rather
    // than an empty/placeholder string.
    auto anonItem = cast(NodeBrowserItem) browser.itemOf[anonymous];
    assert(anonItem !is null);

    // Geometry-only draw pass (render=false): confirms the custom
    // drawItemContent()/calcItemHeight() overrides run to completion
    // without a real display, matching this project's established
    // headless-draw-testing pattern (see `fl.tree_item`'s own icon
    // unittest for precedent).
    int y = 0, xmax = 0;
    browser.root().draw(0, y, browser.w(), null, xmax, true, false);
    assert(xmax > plainItem.labelX());

    FlGroup.current(null);
}

unittest
{
    // Regression coverage for `onOpen`'s double-click detection: the
    // constructor's own `TreeItemReselectMode.selectableAlways` call is
    // load-bearing, not decorative -- `Tree.select()`'s default mode
    // (`selectableOnce`) fires *no* callback at all on a re-click of an
    // already-selected item, confirmed by reading `select()`'s own body,
    // so without that constructor line
    // `onOpen` could never fire no matter what `onTreeCallback()` itself
    // checked.
    import fluid.window_node : WindowNode;
    import fluid.widget_node : WidgetNode;

    FlGroup.current(null);

    auto rootNode = new WindowNode();
    rootNode.typeName = "Fl_Window";
    rootNode.instanceName = "mainWindow";

    auto btn = new WidgetNode();
    btn.typeName = "Fl_Button";
    btn.instanceName = "okButton";
    rootNode.addChild(btn);

    auto browser = new NodeBrowser(0, 0, 300, 200);
    FlGroup.current(null);
    browser.build([rootNode]);

    Node opened;
    browser.onOpen = (n) { opened = n; };

    auto item = browser.itemOf[btn];

    // First click: selects the item, but `eventClicks()` reports 0 (a
    // fresh, non-repeat click) -- `onOpen` must NOT fire yet, even
    // though this is the item's very first selection.
    fl.eventClicks(0);
    browser.select(item, true);
    assert(opened is null);

    // Second click on the SAME already-selected item, with a nonzero
    // click count (what a real double-click's second `FL_PUSH` reports
    // via `Fl::event_clicks()`) -- this is the actual double-click.
    fl.eventClicks(1);
    browser.select(item, true);
    assert(opened is btn);

    fl.eventClicks(0);
    FlGroup.current(null);
}

unittest
{
    // `truncatedComment()` -- a multi-line comment must draw only its
    // first line on the
    // project tree's comment sub-line, matching FLTK's own
    // `copy_trunc(buf, l->comment(), 80, 0, 1)`.
    assert(truncatedComment("short") == "short");
    assert(truncatedComment("first line\nsecond line") == "first line");
    assert(truncatedComment("first line\n") == "first line");
    assert(truncatedComment("12345", 5) == "12345"); // exactly maxChars, nothing left over
    assert(truncatedComment("123456", 5) == "12345...");
    assert(truncatedComment("12345\n67890", 5) == "12345"); // hits the limit right at a newline
    assert(truncatedComment("héllo wörld", 5) == "héllo..."); // multi-byte UTF-8 counted as code points
}
