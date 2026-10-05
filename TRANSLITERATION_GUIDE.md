# C++ -> D transliteration guide

How to convert a real FLTK `.fl` file (or the raw C++ Fluid ships inside
one, like `fluid/panels/widget_panel.fl`) into this project's own
D-embedded `.fl` dialect. This is a *reference*, not a changelog — it
describes the dialect as it stands today. `FLUID_DIALECT.md` covers the
dialect's own grammar/authoring rules once a file is already in D;
this document is specifically about the conversion step, from raw C++
to that dialect. The history of how each rule was discovered lives in
git history; this document exists so that history doesn't have to be
re-read every time.

Written for whoever (human or Claude) is about to sit down and convert
a `.fl` file's `code`/`callback`/`setup`/`decl` bodies from C++ to D.
`panels/widget_panel.fl`, the largest such conversion, is finished; this
document is the general-purpose technique.

## The core idea: the `.fl` file already contains D

This is the single most important thing to understand before touching
anything. Early in this project, `.fl` files were still C++ shaped
(`Fl_`-prefixed type names, `o->foo()`, `Fl::bar()`, `FL_SOME_CONST`),
and `code_writer.d` carried a whole mechanical C++-to-D transpiler layer
to cope: `->` to `.`, pointer-declaration rewriting, cast-stripping,
`Fl::` to `fl.core.`, `FL_*` to camelCase, and more. That transpiler is
**gone**. It was replaced by a dialect change at the source: a `.fl`
file written for this project uses fldtk's own D class names directly
(`Window`, `Button`, `RoundButton`, no `Fl_` prefix) and its
`code`/`code0`-`code3`/`callback`/`setup`/`decl` bodies contain real,
already-correct, hand-written D.

**What this means in practice**: converting a file is not a mechanical
find-and-replace pass you can fully automate. It's reading each C++
snippet, understanding what it does, and writing the D that does the
same thing — using this project's own already-ported API the same way
you'd write any other hand-authored `.d` file in this codebase.
`code_writer.d`'s job is just tree-assembly and name-wiring; it emits
what you wrote close to verbatim (see `translateOwnSlot()`, the one
remaining substitution — just the `o` convention below).

## Finding the right D name for a C++ symbol

Before transliterating any given line, you need to know what its
FLTK-C++ symbols map to in this D port. **Never guess a plausible-
sounding name** — this project has been burned by that before (see the
project's own "Verify names against real FLTK source" convention).
Instead:

1. Check `PORTING.md`'s file-by-file table for the FLTK header
   (`FL/Fl_Whatever.H`) to find which `fl.*` module ported it, and
   whether that port is `Done`/`Partial`/`Deferred`.
2. Read that module's actual D source (`source/fl/whatever.d`) — the
   real signature, not a remembered one. Method names are camelCase
   versions of the FLTK method (`label_image_spacing()` ->
   `labelImageSpacing()`); type names are PascalCase without the `Fl_`
   prefix (`Fl_Widget` -> `Widget`, `Fl_Group` -> `Group`).
3. For the old monolithic `Fl::` static surface specifically: most of
   it now lives in `fl.core` (event state, `run()`/`wait()`, timers,
   `grab()`/`modal()`, clipboard, `add_fd()`, schemes — see CONVENTIONS.md's
   "Namespace mapping" section). But plenty of `fl_something()` free
   functions FLTK never were `Fl::` members at all, and live in
   their own dedicated module instead — `fl_alert()`/`fl_message()` in
   `fl.ask`, `fl_color()`/`fl_rect()`/`fl_font()` in `fl.draw`,
   `fl_filename_name()` in `fl.filename`, and so on. `PORTING.md` is
   the authoritative index; don't assume everything routes through
   `fl.core`.
4. If a symbol genuinely isn't ported yet, that's a real gap, not
   something to work around inline — check `PORTING.md`, and if it's
   missing, that's its own task (port it for real) before the file that
   needs it can be finished.

Because this lookup step is real work, don't try to memorize a static
C++-name -> D-name table here; one would drift out of date immediately
as more of `fl.*` gets ported. This document only covers mappings that
are **structural** (true regardless of which FLTK module is involved)
and the **`.fl`-dialect conventions** specific to this project's own
Fluid port.

## Structural C++ -> D mappings

These apply everywhere, independent of which specific FLTK API is
involved:

| C++ | D |
|---|---|
| `o->foo()` (pointer member access) | `o.foo()` |
| `nullptr` / `NULL` | `null` |
| `dynamic_cast<Foo*>(x)` | `cast(Foo) x` |
| `static_cast<Foo*>(x)` / `(Foo*)x` (C-style cast) | `cast(Foo) x` |
| `const char*` | `string` (see CONVENTIONS.md's `label()`/`tooltip()` note — D `string` is GC-owned/immutable, no manual copy/free bookkeeping needed) |
| `std::string` | `string` |
| `std::vector<T>` | `T[]` |
| `std::map<K, V>` | `V[K]` |
| `std::function<void(Fl_Widget*)>` | `void delegate(Widget)` |
| `printf(...)` / `fprintf(stderr, ...)` | `writefln(...)` / `stderr.writefln(...)` (`std.stdio`) |
| `sprintf(buf, fmt, ...)` | `std.format.format(fmt, ...)` returning a `string` directly — no buffer |
| `strcmp(a, b) == 0` | `a == b` |
| `strlen(s)` | `s.length` |
| `new Foo(args)` | `new Foo(args)` — same syntax, but see "GC, not manual delete" below |
| `delete x;` | usually nothing at all (GC) — see "GC, not manual delete" below for the one real exception |
| `this->foo()` | `this.foo()`, or just `foo()` (D doesn't require `this->`) |
| `ClassName::staticMember` | `ClassName.staticMember` |
| `namespace Foo { ... }` | usually a D module (`fl.core`, not a wrapper class — see CONVENTIONS.md's namespace-mapping note) |
| `Fl_Widget*`, `Fl_Group*`, ... | `Widget`, `Group`, ... — D classes are always reference types, so there is no pointer/value distinction to carry over; drop the `*` entirely |
| `virtual`/override without a keyword | D requires an explicit `override` on the overriding method |
| `T& ref` / `T* ptr` out-parameters | usually `ref T` in D, or just return a value — check the already-ported signature rather than guessing |
| `a ? b : c` | same, no change |
| `#include "Foo.h"` | a D `import foo;` (or nothing, if `import fl;`/an existing wholesale import already covers it) — **never** a literal `#include` line; see "A raw `#include` or `::`-scoped name is a hard error" below |
| C++ `enum`/`enum class` | usually an already-ported D `enum` in the relevant `fl.*` module — look it up, don't recreate it |

### GC, not manual `delete`

Most C++ `delete x;` calls simply disappear — the D garbage collector
owns the object once nothing references it. The one real exception:
**`delete this;` inside a widget's own callback** must become
`fl.core.deleteWidget(this);`, never `destroy(this);`. `destroy()`
would leave the callback that's still executing running on a destroyed
object; `fl.core.deleteWidget()` (ported faithfully from
`Fl::delete_widget()`) defers the actual destruction to the next safe
point (the start of the next `wait()`/`check()`), exactly matching
FLTK's own reason for existing. This is also why real FLTK's own
`Fl_Widget_Tracker` pattern exists (watching whether a widget got
deleted out from under a callback mid-execution) — ported here as
`fl.widget_tracker.WidgetTracker`; reach for it wherever FLTK's own
callback code constructs an `Fl_Widget_Tracker` to guard against this.

### Truthiness: a `Widget`-returning accessor is never implicitly bool

C's/C++'s pointer truthiness (`if (!Fl::pushed())`, `if (Fl::focus())`)
does not carry over — D does not implicitly convert a class reference
to `bool`. Any FLTK accessor that returns a widget pointer for
"unset" purposes (`Fl::pushed()`, `Fl::focus()`, `Fl::belowmouse()`,
`Widget::window()`, ...) needs an explicit `is null`/`!is null` check
in D: `!Fl::pushed()` becomes `fl.core.pushed() is null`, not
`!fl.core.pushed()` (the latter is a compile error). Found for real
converting `fast_slow.fl`; a general rule for any `.fl` callback
testing a `Widget`-returning accessor.

### A raw `#include` or `::`-scoped name is a hard error, on purpose

`code_writer.d`'s `emitSnippetLines()` throws if any code/callback/
setup/decl line starts with a C preprocessor directive
(`#include`/`#define`/`#ifdef`/...), and `collectClassOverrideImports()`
throws if a `classOverride` contains `::` (a C++ namespace-qualified
name, e.g. `fluid::widget::Formula_Input`). This is deliberate: it's
exactly the signal that a `.fl` file (or the one snippet you're
converting) still contains raw, unconverted C++ rather than this
project's dialect — see that module's own doc comment for what this
guards against (without it, a raw-C++ `.fl` would run through `fluid -c`
in total silence and emit literally-uncompilable `#include` lines
straight into the generated `.d`). If you hit this
error while converting a file, it means you missed a spot, not that
the tooling is wrong.

### Importing `fluid.*`

Every generated `.d` file starts with a wholesale `import fl;`.
`fl.preferences` exports its own `PreferencesNode` class (not `Node`), so
a bare `Node` in a `.fl` file always means `fluid.node.Node` and needs no
disambiguating import.

`fluid/package.d` is an aggregator module, matching `fl/package.d`'s own
pattern: a single top-level `decl {import fluid;} {private local}` (once per
`.fl` file, not once per type) reaches *any* `fluid.*` type or function.
Every real panel (`widget_panel.fl`, `settings_panel.fl`, ...) does it this
way.

The aggregator does not cover two things: `fluid.app`/`fluid.bootstrap`
(both real `void main()` entry points, deliberately excluded) and a
sibling *generated* panel module (`widget_panel_grid_tab` and similar
aren't under the `fluid.*` namespace at all — they're bare top-level
modules, imported by their own file name).

If a similarly bogus-looking type error ever recurs for a bare,
unqualified type name, `pragma(msg, __traits(fullyQualifiedName,
typeof(n)))` in a minimal repro is the fastest way to confirm which
symbol actually resolved.

## The `.fl`-dialect conventions

These are specific to how *this project's* `.fl` format itself works,
on top of the plain C++-to-D mapping above.

### The `o` convention

Every callback/`code0`-`code3` body refers to "the widget this code
concerns" as a bare `o`, matching FLTK's own documented `Fl_Callback`
parameter-naming convention (`void (*)(Fl_Widget *o, void *v)`). Two
different physical contexts both use it:

- Inside `code0`-`code3` (construction-time code, attached to a
  widget's own property list): `o` means "this widget's own variable"
  — already the widget's real, correctly-typed name at that point.
- Inside a `callback { ... }` property (or a named callback-shaped
  `Function`'s body): `o` means "the freshly cast closure local" —
  `code_writer.d` generates `.callback((raw) { auto o = cast(X) raw;
  <your snippet>; });` around whatever you write. Just write `o.value()`,
  `o.label()`, etc. directly; the cast is handled for you.

A named `Function` taking a differently-named parameter (e.g.
`radio.fl`'s `buttonCB(Button b)`) follows the same rule with that
parameter's own name instead of `o`.

**`raw` is effectively reserved inside a `callback { ... }` property
body too, for the same reason.** It's the *outer* closure parameter
name in `.callback((raw) { auto o = cast(X) raw; <your snippet>; });`
— still lexically open while your snippet runs, so a local variable in
your own code named `raw` is a hard shadowing error (`Error: variable
`raw` is shadowing variable ...__lambda...raw`), not a warning. Found
converting `widget_panel.fl`'s `class_tabs` page (a `string raw =
o.value();` line, innocuous-looking, broke this way). Pick a different
name for anything holding a widget's own raw value read out of `o` —
`rawValue`, `rawName`, whatever fits — never `raw` itself.

### Brace style inside code bodies: GNU, not K&R

Multi-line control flow (`if`/`else`, loops, lambda literals) written
*inside* a `code`/`code0`-`code3`/`callback` property's value uses GNU
style (Allman, with the opening brace given one extra indent level
beyond its own statement), not K&R:

```
if (o.value())
  {
    writeln("Shave.");
  }
else
  {
    writeln("Don't shave.");
  }
```

not `if (...) { ... } else { ... }`. This only affects how the emitted
D is formatted (`emitSnippetLines()` re-indents everything to the
writer's own current level regardless), but apply it anyway for
consistency across every `.fl` file's embedded code.

### A trailing flags group doesn't need its own line

A property like `code {BODY} {FLAGS}` has a second, usually-near-empty
trailing brace group for Fluid's own per-node editor state (`selected`,
`open`, ...). Even when `BODY` is multi-line, write the trailing group
on one line if its own content is short: `...} {selected}`, not
`...} {selected\n  }`. Real FLTK's Fluid's own writer does split it
onto its own line, but there's no reason to inherit that habit here —
see `FLUID_DIALECT.md`'s "Don't split a trailing flags group onto its
own line" section for the full reasoning.

### An anonymous node still needs an empty `{}` name slot

`TypeName {properties} [{children}]` is *not* the full grammar for a
node with no instance name — it needs an explicit empty brace pair
first: `TypeName {} {properties} [{children}]`. Easy to miss because
plenty of real examples only ever show this for a childless node
(`Box {} {label ...}`), which looks at a glance like `{}` might be an
"empty properties, real content follows" idiom rather than a genuine
name slot — it's the name slot. Skipping it doesn't error where you'd
expect: the reader's own property-parsing loop happily consumes your
*properties* block as if hunting for the name slot's own closing `}`,
then fails much later (`expected '{' to start <Type>'s children`, or,
one level down, `expected '{' to start <Type>'s property list`) at
whatever node happens to come next — a confusing error far from the
real omission. Found converting `widget_panel.fl`'s `declblock_tabs`
page: every widget you *name* (which is most of them, in practice —
this project's dialect prefers real names, see "Verbatim naming for
named widgets" below) sidesteps this entirely, so it's easy to go
several pages without ever hitting it, then hit it hard on the first
page with FLTK's own decorative anonymous `Box`/`Group` elements.
**Given a name for every widget avoids this class of bug entirely** —
worth doing even where FLTK itself left something anonymous,
unless preserving the exact "which widgets does FLTK name" shape
specifically matters for what you're converting.

### A literal `#` needs `\#`, anywhere, not just `#include` lines

`decl {\#include "Foo.h"}`'s escaped hash is the example every already-
converted panel shows, which makes it easy to assume the escaping is
specifically an `#include`/preprocessor-directive thing. It isn't —
it's about the `.fl` format's own value grammar, and it applies to
*any* literal `#` inside *any* property value, including a plain D
string literal inside a `code { ... }` body that happens to contain
one (`n.instanceName = "#ifdef X";` breaks; `"\#ifdef X"` doesn't).
Unescaped, the parser doesn't error at the `#` itself — it keeps
consuming text looking for a closing quote/brace in the wrong place,
surfacing as a confusing D syntax error far downstream in the
*generated* file instead of a clean `.fl`-level one. A `tooltip {...}`
value with a literal `` ` `` and `\#` together (`` tooltip {`\#ifdef` or
similar} ``) is real, existing, working FLTK text — confirms the
escaping rule is about the raw character appearing anywhere in a
value, not about which property it's in.

### Two shapes of named `Function`

A named top-level `Function` node splits into two shapes,
disambiguated by `isCallbackShape()` in `code_writer.d`:

- **Callback-shaped**: `void` (or unset) return type *and* exactly one
  parameter — matching `Fl_Callback`'s own `void(Widget)` shape. Meant
  to be used bare as a `.callback(name)` value. Becomes a module-level
  `void delegate(Widget) name;` variable, assigned a delegate literal.
  (D forbids implicitly converting a plain function to a delegate, so
  this can't just be an ordinary `void name(Widget o) { ... }`
  function — confirmed via a minimal repro.)
- **Plain**: anything else — a different return type (a *factory* that
  produces a callback, not one directly), or a different parameter
  count/shape (a zero-parameter builder like `makeWindow()`). Becomes
  an ordinary top-level D function, signature and body emitted
  verbatim.

FLTK's `Fl_Callback*`-cast-and-`user_data`-trampoline machinery
(needed in C++ purely because a plain function pointer can't close over
state) has no D equivalent to port at all — see CONVENTIONS.md's
"Callbacks are D delegates" porting convention. Where FLTK code
uses `user_data()` to smuggle context through a trampoline, the D
version just captures that context directly in a closure.

### `Class_Node`: only for a real base-class relationship, or genuine multiple instances

- `class Name : Base { ... }` (a genuine base-class relationship, e.g.
  a window subclass overriding a virtual method) always becomes a
  real D class. The biggest simplification lands here too: FLTK
  needs a `static` trampoline method forwarding to a real virtual
  method purely because a C++ callback can't close over `this`; a D
  closure created inside a real method body (typically the
  constructor) already captures its enclosing instance, so the
  trampoline is simply gone.
- A base-less `class Name { ... }` is not automatic just because
  FLTK wrote a class. **The real rule is "does the driver need
  more than one instance," not whether it has a base class.** If
  something FLTK wrapped in a class purely as a C++ workaround
  (e.g. so several small static+inline trampoline functions could
  reach a shared sibling widget) is only ever instantiated once, it
  flattens cleanly into plain module-level widget globals plus a named
  builder `Function`. If the driver genuinely constructs more than one
  instance of it, it needs a real (if base-less) D class after all —
  perfectly valid D syntax (`class Name { ... }`, implicit `Object`
  base). Check the driver's own intent, or how many times the class
  is meaningfully reusable, before assuming either way.

### Grammar: the base class goes *inside* the properties block

`class App : Window { ... }` is wrong — a class node's base class is
introduced by a bare `:` *property* inside the first (properties)
block: `class App {: Window\n} { ... }`. **The properties block is
required even when empty**: write `class Name {} { ... }` for a
base-less class, never `class Name { ... }` — omitting the empty `{}`
makes the reader's tolerant-of-unknown-properties fallback silently
swallow the entire children block as a bogus property value instead of
erroring, producing a class with fields but no methods and no warning
at all.

### Naming: verbatim for named widgets, a small fixed scheme for anonymous ones

A named widget's `.fl` instance name (`Output cbInfo { ... }`) *is*
the generated D variable name, byte for byte — no camelCasing, no
suffix. Write exactly the D identifier you want.

Anonymous widgets follow a fixed scheme (chosen because D, unlike
C++, treats a still-open nested scope shadowing an outer variable of
the same name as a hard compile error, even when the outer one is
never used again — but *sequential, already-closed* sibling scopes
reusing the same name compile fine):

- **The top-level window**: always `w` (it needs to outlive its own
  children block, for `.show(args)` after `.end()`).
- **Anonymous `Group`s with children**: named by nesting *depth*
  (`g1`, `g2`, ...) — a group's own children need `o` for themselves,
  so the group can't claim it too. Sibling groups at the same depth
  safely share a name (their scopes never overlap); only genuine
  nesting needs a distinct name, which incrementing depth guarantees.
- **Everything else** (anonymous leaf widgets, and any node whose
  children become an array literal rather than a nested block): plain
  `o`, wrapped in its own `{ }` block.

One conflict this scheme creates on its own: an anonymous leaf widget
named `o` that also has its own `callback` property would otherwise
need its callback closure to *redeclare* `o` while the widget's own
`o` is still live — exactly the hard-error case above. `writeCallback()`
handles this already: when the widget's own variable is already named
`o`, the closure skips introducing a new cast variable and just
captures the outer `o` directly (already correctly typed). This is
handled for you by the generator; just be aware of it if you're
debugging generated output that looks like it's missing a cast.

### A same-named module/class needs a selective import

A `class` override property naming an externally-defined D class (e.g.
a hand-written subclass used in place of the plain type's default)
needs that class's module imported. If the module and the class it
exports share the exact same name — the common convention for this
project's own hand-written classes — a plain `import Foo;` is
genuinely ambiguous (`import Foo.Foo is used as a type`, confirmed via
a minimal `dmd` repro): the bare identifier resolves to the *module*,
not the class inside it. `code_writer.d` already emits a selective
import (`import Foo : Foo;`) to work around this, assuming the
single-class-per-module convention — if a future override lives in a
differently-named module, that assumption needs revisiting.

## The property-panel "LOAD/CHANGED" pattern

This one is specific to converting a **property-editing dialog** —
exactly what `widget_panel.fl` is, and the main reason this section
exists. FLTK's Fluid's own property-panel fields (and its own
`widget_panel.fl`) share one callback per field, gated on the C++
`void*` parameter being the sentinel `LOAD` or not:

```cpp
void label_cb(Fl_Input* i, void* v) {
  if (v == LOAD) {
    i->value(current_widget->label());
  } else {
    if (i->changed()) {
      for (Node* o = Fluid.proj.tree.first; o; o = o->next)
        if (o->selected && o->is_widget())
          ((Widget_Node*)o)->label(i->value());
      // ... undo checkpointing, mark project modified, etc.
    }
  }
}
```

**The target for `widget_panel.fl` is FLTK's own flat structure**
— a plain `Function {makeWidgetPanel()}` returning `thePanel`, module-
level globals for every named field (`Fl_Input* wp_gui_label;` becomes
`Input wpGuiLabel;` at module scope), and one module-level named
`Function` per FLTK callback (`label_cb` -> `Function {labelCb
(Widget o)} {...}`) — the same shape every other already-converted
panel in this project already uses (`about_panel.fl`, `settings_panel.
fl`, `function_panel.fl`, ...). **`fluid/panels/widget_panel.d` (the
current hand-written dialog) is reference material only — what fields
exist and roughly what they do — not the architecture to target.** It
is a `class WidgetPanelDialog : Window`, a design invented during an
earlier "restart" session that departed from FLTK's own structure
without that being a deliberate, agreed decision; treating it as the
porting target would mean re-introducing that same departure on
purpose. Port FLTK's literal structure instead, and treat anything
`widget_panel.d` added on its own authority (an "External Editor"
button with no FLTK counterpart, a one-off `xywh` shift to make
room for it, an ambient `normalSize` override standing in for
FLTK's own per-widget `labelsize 11`) as exactly that: something
`widget_panel.d` invented, not something to carry forward. If one of
those turns out to genuinely be worth keeping, raise it rather than
silently inheriting it.

**A plain `void delegate(Widget)` callback can't carry the `void*`
sentinel** (see CONVENTIONS.md's "Callbacks are D delegates" convention —
no `user_data`/second-argument slot exists in this port at all), so the
sentinel dispatch itself doesn't transliterate literally. It splits
into two pieces, matching FLTK's own two branches:

1. **A shared `propagateLoadX(Node n)`-style function** (named after
   FLTK's own `propagate_load()`, the cascading-LOAD mechanism it
   replaces) populates the field(s) directly — matching FLTK's own
   `if (v == LOAD)` branch, called once per selection change rather
   than dispatched as a fake callback invocation.
2. **Each field's own real `.callback()` property**, containing *only*
   FLTK's `else` branch (the store-side logic) — matching FLTK's
   *own* callback function, minus the `if (v == LOAD) {...} else {`
   wrapper and its closing brace.

**No re-entrancy guard is needed, and this isn't a simplification —
it's what FLTK itself relies on too.** A plain value setter
(`i->value(x)`, `.buffer().text(x)`) does not itself invoke the
widget's own `.callback()`/`do_callback()` in FLTK; only a real
interactive event (gated by the widget's own `when()` flags) does.
FLTK's `propagate_load()` only reaches each field's `else` branch
by *directly calling the callback function itself* with the `LOAD`
sentinel — an explicit, deliberate dispatch, not a side effect of
setting a value — so nothing in the D translation needs a `loading_`-
style flag to prevent step 1 from re-triggering step 2 either.
Confirmed via a real generate-and-`dmd`-compile pilot converting
`code_tabs` (`widget_panel.fl`'s smallest page): the populate function
calls `codeText.buffer().text(nd.instanceName);` directly, and the
widget's own `callback` property (carrying only the store-side logic)
never fires as a result.

Concretely, `label_cb` above becomes:

```
decl {private Node currentNode_;} {private local}

Function {propagateLoadLabel(Node n)} {open return_type void
} {
  code {currentNode_ = n;
wpGuiLabel.value(n.label);} {}
}
```

and, on the `Input` field's own declaration:

```
Input wpGuiLabel {
  callback {if (currentNode_ is null) return;
currentNode_.label = o.value();}
  xywh {...}
}
```

(Multi-selection apply — FLTK's own `for (Node* o = Fluid.proj.
tree.first; ...) if (o->selected...)` loop — and undo/dirty-flag
bookkeeping both still need a real connection to `gui_main.d`'s own
state once this is wired in for real, not just piloted in isolation:
matching how already-converted flat panels reach out to the host
application today (`settings_panel.fl`'s own `decl {import fluid.
gui_main : ...;}`, calling free functions directly) is the established,
flat-design-compatible mechanism — no delegate/callback-field
indirection needed, unlike `widget_panel.d`'s own `onBeforeEdit`/
`onEdited` design.)

**When converting a field, still check whether `widget_panel.d`
already implements it** (grep its own extensive `// FLTK: <cxx
function name>` comments — 254 of them at last count) for what the
field is *for* and what edge cases it handles — genuinely useful
research even though its own method-per-field, class-scoped shape
isn't what you're writing.

## Casting between sibling ancestor types (`dynamic_cast` walks)

FLTK's Fluid code frequently walks a node's ancestor chain checking
each level's dynamic type, e.g. `check_redraw_corresponding_parent()`
(deciding whether a selected node sits inside a `Tabs`'s or `Wizard`'s
hidden page):

```cpp
for (Node *i = s; i && i->parent; i = i->parent) {
  if (dynamic_cast<Group_Node*>(i) && prev_parent) {
    if (dynamic_cast<Tabs_Node*>(i)) { ((Fl_Tabs*)...)->value(...); return; }
    if (dynamic_cast<Wizard_Node*>(i)) { ((Fl_Wizard*)...)->value(...); return; }
  }
  ...
}
```

Translates directly — `dynamic_cast<T*>(x)` (used as a boolean "is it
this type") becomes `cast(T) x !is null`, or more idiomatically D's
`if (auto t = cast(T) x)` pattern, which both tests *and* gives you the
correctly-typed reference in one step:

```d
for (Node i = s; i !is null; i = i.parent)
{
    auto iw = i in live.widgetOf;
    if (iw !is null && cast(Group)(*iw) !is null && prevParent !is null)
    {
        auto pw = prevParent in live.widgetOf;
        if (pw !is null)
        {
            if (auto tabs = cast(Tabs)(*iw)) { tabs.value(*pw); return; }
            if (auto wiz  = cast(Wizard)(*iw)) { wiz.value(*pw); return; }
        }
    }
    ...
}
```

No C-style `((Fl_Tabs*)...)` re-cast needed afterward — `if (auto x =
cast(T) y)` already gives you `x` typed as `T` inside that branch. (Full
version, including the `prevParent`-tracking half of the loop: `gui_main.
d`'s own `revealAncestorTabs()`, ported the same way for the interactive
editor's own selection-change handling, not `widget_panel.fl` itself.)

## Other porting conventions that still apply

Everything in CONVENTIONS.md's "Porting conventions" section applies to
transliterated code exactly as it applies to hand-written `fl.*`
modules — this guide doesn't repeat all of it, just flags where it's
most likely to come up while converting a Fluid panel:

- **Trailing-underscore private fields** (`x_`, not `x`) when a
  converted class needs a private field with the same name as a public
  accessor.
- **The GC-finalizer hazard**: a converted class with a destructor that
  reaches into other objects needs the `GC.inFinalizer()` guard.
- **D's vtable is fixed for an object's whole lifetime** — no C++-style
  rewinding during destruction or staging during construction. If
  converted code relies on a virtual call from a base constructor/
  destructor reaching only that base's own version (a real C++
  behavior), re-derive whether the D port needs an explicit workaround
  or gets the more-permissive D behavior for free.
- **Module-level state is thread-local by default** — mark a converted
  global `__gshared` if it's read from more than one thread.

## Worked example checklist

When converting one field/callback/decl block:

1. Read the real FLTK C++ (FLTK's `fluid/...`), not
   this project's already-copied reference `.fl` — the copy is only
   there so you don't have to keep the two checkouts open side by
   side, but the checked-out FLTK source is the ground truth for the
   file layout it belongs to (`.cxx`/`.h` split, surrounding context).
2. Check whether `widget_panel.d` (or another already-hand-written
   panel/dialog) already implements the same field — useful research
   for what it's for and what edge cases it handles, but not the D
   reference to transliterate from; for `widget_panel.fl` specifically,
   its own class-based architecture is a known departure from FLTK
   this conversion is deliberately not repeating (see "The property-
   panel LOAD/CHANGED pattern" above).
3. For every FLTK symbol involved, look up its real fldtk name/
   signature per "Finding the right D name for a C++ symbol" above.
   Don't guess.
4. Apply the structural mappings, then the `.fl`-dialect conventions,
   then (for a property-panel field specifically) the LOAD/CHANGED
   split.
5. Regenerate via `fluid -c` (or, for `widget_panel.fl` specifically,
   once enough of it is converted to attempt a real build) and confirm
   it compiles — `code_writer.d`'s guards will loudly reject anything
   still containing raw C++, which is a useful sanity check on its own.
6. Update `PORTING.md`'s own status for
   whatever just got converted, so that—per `CONVENTIONS.md`—nothing is left stale:
   don't leave a stale "not yet converted" note next to
   code that now is.
