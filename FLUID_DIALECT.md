# The fldtk `.fl` dialect: how to write one

A reference for authoring or editing a `.fl` project file for this
project's own Fluid port — `fluid/panels/*.fl`, `fluid/templates/*.fl`,
and any `samples/*/*.fl`. It holds durable rules for the text itself;
per-module implementation status lives in `PORTING.md`'s `## Fluid`
section.

For current implementation status (what's built, what's a known gap,
file by file) see `PORTING.md`'s `## Fluid` section. For build/run
commands (`fluid -c`, `rdmd fluid/buildfluid.d`, etc.) see `CLAUDE.md`.

## The dialect pivot: `.fl` files contain literal D, not C++

Upstream FLTK's own `.fl` files store `Fl_`-prefixed C++ type names and
`code`/`code0`-`code3`/`callback` bodies full of real C++ (`o->foo()`,
`Fl::bar()`, `FL_SOME_CONST`, C-style casts, `sprintf`/`printf`). This
project's own `.fl` files use fldtk's own D class names directly
(`Window`, `Button`, `RoundButton`, ... — no `Fl_` prefix), and every
`code`/`code0`-`code3`/`callback` body contains real, already-correct D,
written by hand by whoever authors the file. There is no C++-to-D
transpiler in `code_writer.d` — `fl.` mostly means "tree-assembly and
name-wiring, emit code close to verbatim," not "translate."

### The `o` convention

Every callback/`code0`-`code3` body refers to "the widget this code
concerns" as a bare `o`, matching FLTK's own documented `Fl_Callback`
parameter-naming convention. Two different physical contexts both use
it:

- Inside `code0`-`code3`/`setup` (construction-time code, attached to a
  widget's own property list): `o` means "this widget's own variable"
  (which already has a real, distinct name) — the writer substitutes it.
- Inside a `callback { ... }` property, or a named callback-shaped
  Function's body: `o` means "the freshly cast closure local" the writer
  itself introduces (`auto o = cast(X) raw;`) — write it as-is, no
  substitution needed. The closure's own outer, `Widget`-typed parameter
  is named `raw` specifically so it doesn't collide with that inner `o`
  (D forbids a nested declaration shadowing its own enclosing lambda
  parameter).

## Brace style inside `code`/`callback` bodies: GNU, not K&R

Unrelated to the `.fl` grammar's own multi-brace-group-per-line
convention (`Type {name} {`, a bare `} {` between properties and
children — that's the real `.fl` file format and stays as-is). This is
about how to format actual multi-line D code once it's written *inside*
a `code`/`code0`-`code3`/`callback` property's own value: use GNU style
(Allman, with the opening brace given one extra level of indent beyond
the statement it belongs to):

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

not K&R (`if (o.value()) {`). This is purely a `.fl`-source readability
convention — `emitSnippetLines()` strips and re-emits each line at the
writer's own current indent level regardless of source indentation, so
it has no effect on whether generated output compiles, only on how the
generated `.d` file's own line breaks land. Apply to every `.fl` file's
embedded code.

## The `.fl` file's own structure: same style, written by Fluid

`ProjectWriter` (Save / `fluid -c`-adjacent normalization) lays out the
file's own brace groups the same way, so a saved `.fl` looks like this
rather than FLTK's `Type name {` K&R form:

```
Group {}
  {
    xywh {15 15 80 128}
  }
  {
    Button {}
      {
        label {b&1}
        xywh {15 15 80 32}
      }
  }
```

The property group and the children group each open with a `{` on its
own line, one level deeper than the node header; contents go one level
deeper still; the closing `}` aligns with its `{`. One-line `name {value}`
properties stay inline. The file-level option blocks (`shell_commands`,
`snap`, with their nested `command`/`suite`/`preset` groups) use the same
layout; a `preset`'s version tag `1` is the first line inside its braces.
(`i18n_*` has no blocks, just flat `key value` lines.) Hand-authored `.fl` files may keep the compact
K&R form for the file structure (the reader ignores whitespace) — it is
normalized the next time Fluid saves them.

## Don't split a trailing flags group onto its own line

A property like `code {BODY} {FLAGS}` has a second, trailing brace group
for Fluid's own per-node editor state (`selected`, `open`, etc., often
empty). When `BODY` is multi-line, don't let the trailing group's own
closing `}` land alone on its own line for no reason:

```
code {...
...
writeln(msg);} {selected}
```

not

```
code {...
...
writeln(msg);} {selected
  }
```

A trailing flags group only gets its own line(s) if its own content
genuinely needs them, never just because the *value before it* happened
to be multi-line. (Real upstream Fluid's own `Code_Writer` does produce
the second, worse shape — it's an inherited C++ habit with no reason to
carry over here, since nothing depends on byte-for-byte matching
upstream's own save format.)

## Two shapes of named Function

A named top-level `Function` node splits into two shapes, disambiguated
by `isCallbackShape()` in `code_writer.d`:

- **Callback-shaped**: `return_type` is `void` (or unset) *and* it takes
  exactly one parameter — matching `Fl_Callback`'s own `void(Widget)`
  shape. Meant to be used *bare* as a `.callback(name)` value; becomes a
  module-level `void delegate(Widget) name;` variable assigned a
  delegate literal (D forbids implicitly converting a plain function to
  a delegate, so a real closure is unavoidable).
- **Plain**: anything else — a different return type (a factory that's
  *called* to produce a callback, not assigned directly) or a different
  parameter count (e.g. a zero-parameter window-builder method). Becomes
  an ordinary top-level D function, signature and body emitted verbatim.

## `Class_Node`: only for a real base-class relationship

- **`class Name : Base { ... }`** (a genuine base class) becomes a real
  D class. This is also where the biggest FLTK/C++ simplification lands:
  upstream needs a `static` trampoline method forwarding to a real
  virtual method purely because a C++ callback can't close over `this`;
  a D closure created inside a real method body already captures its
  enclosing instance, so the trampoline is simply gone — the
  constructor's own closure calls the virtual method directly. (`delete
  this` inside a callback still needs `fl.core.deleteWidget(this)`, not
  `destroy(this)` — D's closures remove the need for the trampoline, not
  the deferred-deletion hazard.)
- **`class Name { ... }`** with no base: the real rule isn't "has a base
  or not," it's **"does the driver need more than one instance."** A
  base-less class whose driver only ever constructs one instance
  flattens cleanly into plain module-level widget globals plus a named
  builder Function — no `Class_Node` needed at all. A base-less class
  instantiated more than once still needs a real (if base-less) D class:
  `class Name { ... }`, no `: Base`, which is valid D (implicit `Object`
  base). Check the driver's own intent (or how many times the class is
  meaningfully reusable) before assuming either way.

### Grammar note: the base class goes *inside* the properties block

`class App : Window { ... }` looks natural but is wrong — the reader
expects `TypeName instance_name { properties } [{ children }]`
uniformly, and a class node's base class is introduced by a bare `:`
*property* inside that first block: `class App {: Window\n} { ... }` (or
with other flags: `class App {open : Window\n} { ... }`).

**The properties block is required even when empty**: write `class Name
{} { ... }` for a base-less class, never `class Name { ... }` — without
the empty `{}`, the reader's tolerant-of-unknown-properties fallback
silently swallows the entire children block as a bogus property value of
the class itself (no error, just a class with fields but no methods).
The same applies to any container node with no real children: write
`Group {} { ... } {}` (the trailing `{}` for editor flags), not `Group
{} { ... }` — omitting it doesn't parse.

## Class fields, and a method whose body is a widget tree

- A named widget declared *inside* a class's own method becomes a class
  **field**, not a module-level global.
- A named Function ("plain" shape, see above) can have a real widget
  tree as its body instead of a bare `code { ... }` block, walked the
  same way any other widget tree is.
- A Window inside a class method never gets an automatic `.show(args)`
  call the way the top-level main Function's own window does — `args`
  isn't even in scope inside a class method. `.show()` is the calling
  driver code's own job there.

## A window's own "resizable" isn't always self-referential

A window with no child marked resizable emits `w.resizable(w);` — a
genuine self-reference. But a window that's marked resizable *and* has a
direct child *also* marked resizable emits only
`FlGroup.current().resizable(child);` for the child, no self-reference
for the window at all — the child's own resizable-designation call
already runs (while still inside its own block) and sets the window's
`resizable_` field; a later unconditional self-reference would silently
overwrite that. A window only self-designates when no *direct* child is
also marked resizable.

## Widget naming: verbatim when named, conventional when anonymous

A named widget's `.fl` instance name (`Output cbInfo { ... }`) *is* the
generated D variable name, byte for byte — no camelCasing, no `_`
suffix. Write exactly the D identifier you want.

Anonymous widgets follow a fixed convention instead (chosen so that
nested-and-still-live names never collide, while sequential sibling
blocks safely reuse one — confirmed D allows reusing a name across
sequential, non-overlapping sibling blocks, but never a nested block
shadowing a still-open outer one of the same name):

- **The top-level window**: always `w` — it needs to persist past its
  own children for `.show(args)`, called after `.end()`.
- **Anonymous `Group`s with children**: named by nesting *depth*
  (`g1`, `g2`, ...) — a group's own children need `o` for themselves, so
  the group can't also claim it. Sibling groups at the same depth safely
  share a name; only genuine nesting needs a distinct one.
- **Everything else** (anonymous leaf widgets, and any node whose
  children become an array literal rather than nested blocks — e.g. a
  menu owner): plain `o`, wrapped in its own `{ }` block.
- **If an anonymous leaf widget (named `o`) also has its own `callback`
  property**: the callback closure does *not* introduce a second `auto o
  = cast(X) raw;` — it would try to redeclare `o` while the widget's own
  still-open `o` is live, a hard D error. The closure just captures the
  outer `o` directly instead (already correctly typed). Only a
  genuinely different outer name (a named widget, or `w`/`g1`-style
  container names) needs the closure to introduce its own fresh cast
  variable.

## A same-named module/class needs a selective import

`class Foo` (naming a hand-written subclass instead of the plain type's
own default, e.g. `Box cube { ... class CubeView }`) means the generated
file needs to import the externally-defined class. A plain `import
CubeView;` is genuinely ambiguous when the module and the class it
exports share the exact same name — the bare identifier resolves to the
*module*, not the class inside it. Always a selective import instead:
`import CubeView : CubeView;`. This assumes the common
single-class-per-module convention this project's own hand-written
classes follow (module name == class name).

The same mechanism covers a `class` override that names a real,
already-available fldtk built-in rather than a hand-written companion
(e.g. `Group {} { ... class Window }`, meaning "instantiate a real
`Window` here") — `code_writer.d`'s `builtinClassNames` list (every
class `source/fl/*.d` exports) is checked first, and skips generating an
import for those, since `import fl;` already covers them.

## `decl` nodes: raw D text at module scope

A top-level `decl { ... }` node emits its raw D text (struct/global/
helper-function definitions) verbatim at module scope, right after the
generated file's fixed imports — for text that doesn't belong inside any
one widget's own construction code.

## Two more literal-text gotchas

- **A literal `"` inside a `callback`/`code` body needs the
  double-backslash convention**: write `\\"`, not a bare `\"` — the
  *reader's* own escape handling reduces a bare `\"` to a literal `"`
  byte before the D compiler ever sees it, breaking the string literal
  it was meant to escape. Same rule already applies to `\\n`/`\\\\`.
- **A raw numeric-looking property value** (`shortcut 0xff50`, `step
  0.5`, `minimum 0`) is passed straight through to the matching D setter
  call as already-valid D syntax — no translation table, no runtime
  string-to-number parse. Write it exactly as it should appear in the
  generated D call.

## Known dialect gaps (deliberately deferred, not bugs)

- **No post-children (`final`) code slot.** Only one code slot exists
  per widget (`setup`, emitted before that widget's own children are
  built) — there is no way today to run code *after* a widget's children
  are constructed. Add this the day a real `.fl` file actually needs it,
  not speculatively.
- **No per-widget member-field declaration inside a `class` body.** A
  `ClassNode`'s children are only ever `Function` nodes (methods) today;
  there's no node type for "add a plain field to the enclosing class."
  The module-scope equivalent (`decl {}`, see above) already has a home;
  this is specifically about a field that must live *on the class*.
