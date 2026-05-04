# framec bugs encountered while building Frame Arcade + CCA

This document catalogs the framec issues hit while building this
repository, with minimal reproducers, observed output, expected
output, and the workaround applied. Intended as a hand-off to
the framec maintainer — each bug should be reproducible from the
snippets here without needing the rest of the repo.

| framec | path | version |
|---|---|---|
| `framec` (cargo `~/.cargo/bin/framec`) | `4.0.0` (Apr 2026 release) |
| `framec` (framepiler dev `target/release/framec`) | `4.0.0`, build May 3 |

The framepiler dev build is the one most of these were observed
against. The cargo release is older and lacks features required
by this project (see Issue #3).

---

## Issue #1 — `@@:return(self._method(arg1, arg2))` drops a paren on nested call ✅ **FIXED**

> **Fixed** in framepiler dev build dated May 3 18:02. The
> natural `@@:return(self._teleport(event, N))` form now
> generates clean GDScript with the closing paren intact.
> Workaround removed from `cca/frame/cca.fgd`.

### Severity

Compile-breaking when triggered. The generated GDScript fails to
parse with `Expected closing ")" after call arguments`.

### Where it's hit in this repo

`cca/frame/cca.fgd`, `MagicWordTeleport.try_handle`. The natural
expression is `@@:return(self._teleport(event, dest_room))` — that's
what we wanted to write, and the workaround replaces it with a
local-var spelling.

### Minimal reproducer

```frame
@@[target("gdscript")]

@@system Repro : RefCounted {
    interface:
        do_thing(): Dictionary

    machine:
        $Active {
            do_thing(): Dictionary {
                @@:return(self._inner(1, 2))
            }
        }

    actions:
        _inner(a: int, b: int): Dictionary {
            return {"a": a, "b": b}
        }
}
```

### Observed generated GDScript (the broken line)

```gdscript
func _s_Active_hdl_user_do_thing(__e, compartment):
    ...
    self._context_stack[-1]._return = self._inner(1, 2
    return
    ...
```

Note the missing `)` after `2`. Godot reports
`Parse Error: Expected closing ")" after call arguments`.

### Expected generated GDScript

```gdscript
func _s_Active_hdl_user_do_thing(__e, compartment):
    ...
    self._context_stack[-1]._return = self._inner(1, 2)
    return
    ...
```

### Workaround in this repo

Extract the inner call to a local variable, then `@@:return` the
local:

```frame
do_thing(): Dictionary {
    var r: Dictionary = self._inner(1, 2)
    @@:return(r)
}
```

This generates correctly. The bug appears specific to a function
*call* with arguments inside an `@@:return(...)` form. Single-arg
calls and bare-variable returns are unaffected as far as I've
tested.

### Notes for triage

- The bare-return form `@@:(self._inner(1, 2))` (no `return`)
  may have the same defect — not yet tested.
- The bug is in code emission, not parsing — the `.fgd` parses
  fine; the generated `.gd` is what breaks.

---

## Issue #2 — Parameterized sub-system restore calls `Sub.new()` with zero args ✅ **FIXED**

> **Fixed** in framepiler dev build dated May 3 18:02. The
> generated `restore_state` now threads the saved param
> values through to the constructor:
> `self.dwarf1 = Dwarf.new(__raw_dwarf1.get("seed"))`. This is
> option (1) from the suggested triage. Workaround (default
> param value) removed from `cca/frame/cca.fgd`.

### Severity

Save/restore-breaking for any system that composes a parameterized
sub-system in `domain` and uses `@@[persist]`. The save path
works; the restore path crashes at GDScript parse time with
`Too few arguments for "new()" call. Expected at least 1 but
received 0.`

### Where it's hit in this repo

`cca/frame/cca.fgd`. `Adventure` composes five `Dwarf(seed)`
instances. Each `Dwarf` has a required `seed: int` constructor
parameter. On `Adventure.restore_state`, framec emits
`self.dwarf1 = Dwarf.new()` (zero-arg) before calling
`self.dwarf1.restore_state(...)`. The Dwarf constructor rejects
the call.

### Minimal reproducer

```frame
@@[target("gdscript")]

@@[persist]
@@system Inner(seed: int) : RefCounted {
    operations:
        @@[save]
        save_state(): PackedByteArray {}
        @@[load]
        restore_state(data: PackedByteArray) {}

    interface:
        get_seed(): int

    machine:
        $A {
            get_seed(): int { @@:(self.seed) }
        }

    domain:
        seed: int = seed
}

@@[persist]
@@system Outer : RefCounted {
    operations:
        @@[save]
        save_state(): PackedByteArray {}
        @@[load]
        restore_state(data: PackedByteArray) {}

    machine:
        $A {}

    domain:
        inner = @@Inner(42)
}
```

Steps to reproduce:

```gdscript
var o = Outer.new()
var b = o.save_state()
var o2 = Outer.new()
o2.restore_state(b)   # <-- crashes
```

### Observed generated GDScript (the broken line, in `Outer.restore_state`)

```gdscript
var __raw_inner = state_data.get("inner", null)
if __raw_inner != null:
    self.inner = Inner.new()                  # <-- no args passed
    self.inner.restore_state(var_to_bytes(__raw_inner))
```

`Inner._init(seed: int)` rejects the zero-arg call → parse error.

### Expected behavior

The framec-generated `restore_state` should reconstruct the
sub-system in a way that works regardless of whether the
sub-system has required constructor parameters. Two clean ways:

1. **Thread the saved-state through to construction.** The bytes
   already contain the saved domain (including `seed`); peek at
   it, extract the param values, pass them to the constructor.
2. **Provide a static `Inner.new_for_restore()` (or
   `restore_into(self)`) that bypasses `_init` validation.** The
   subsequent `restore_state` call overwrites every domain field
   anyway, so `_init`-time validation isn't load-bearing here.

The first option is friendlier to user code that does real work
in `_init`; the second is simpler to implement.

### Workaround in this repo

Make every parameter on a persisted parameterized sub-system have
a default value:

```frame
@@system Inner(seed: int = 0) : RefCounted { ... }
```

`Inner.new()` then succeeds; `restore_state` immediately
overwrites `seed` from the saved bytes, so the restored value is
correct. Adventure's composition `inner = @@Inner(42)` continues
to pass `42` at construction; the default is only used by the
generated zero-arg `Inner.new()` inside `restore_state`.

This requires the user to have a sensible default for every
parameter, which is sometimes a stretch. Not all params have
neutral defaults.

### Notes for triage

- Multiple required parameters make the workaround harder
  because the user has to invent multiple default values. A
  fix in framec would be substantially better than asking
  every callsite to defaultify.
- The save side correctly serializes the parameter values in
  the domain (we observe `seed` round-tripping when we use the
  default workaround); only the construction side breaks.

---

## Issue #3 — `@@[save]` / `@@[load]` operation attributes not in cargo `framec` 4.0.0

### Severity

Hard build break against the cargo release. `framec compile`
fails at parse time with
`E002: Parse error in system 'X': Parse error at <byte>:
Unexpected byte '@' (0x40)` on the first occurrence of `@@[save]`
or `@@[load]`.

### Where it's hit in this repo

Every Frame source that uses `@@[persist]`:

- `arcade/frame/scoreboard.fgd`
- `arcade/frame/asteroids.fgd`
- `cca/frame/aspects.fgd`
- `cca/frame/cca.fgd`

### Likely status

This isn't strictly a *bug* — the framepiler dev build supports
these attributes; cargo's release just hasn't caught up. But for
a contributor cloning this repo and running `cargo install
framec`, the failure mode is opaque: the parse error doesn't say
"this attribute is newer than your release."

### Workaround in this repo

The build scripts honor a `FRAMEC` environment variable so the
repo's developers can point at a current framepiler build:

```bash
FRAMEC=/path/to/framepiler/target/release/framec ./build.sh
```

Documented in `arcade/README.md` and `cca/README.md`.

### Suggested triage

Whichever happens first:

1. Cut a new cargo release that includes `@@[save]` /
   `@@[load]` parsing.
2. Improve the parse error to mention the attribute name and
   suggest "your framec may be older than the source requires."

---

## Issue #4 — Transition inside `if` body, then fall-through `@@:(value)` outside the `if`, drops the return value

### Severity

Silently wrong-result. The function declares a non-void return
type (e.g., `bool`, `String`), but a specific control-flow path
returns `Nil` because the generator emits a bare `return` after
the transition and the outer `@@:(value)` never runs.

In GDScript this surfaces at runtime as
`SCRIPT ERROR: Trying to return value of type "Nil" from a
function whose return type is "bool"`. The function's caller
treats the result as falsy; bugs propagate from there.

### Where it's hit in this repo

Two callsites, same shape:

- `cca/frame/cca.fgd`, `EggsIncantation.$WaitingFoo.say` —
  caught and worked around in May 3's "EggsIncantation `$WaitingFoo.say`" pass
  (commit `0b7ced3` had a comment-driven variant; the final fix
  in commit before that round moved the comment outside the
  `if`).
- `ch03-invaders/frame/invaders.fgd`, `Fleet.$Marching.kill_invader`
  and `Fleet.$Stepping.kill_invader` — caught while writing
  ch03's smoke test. The 55th invader kill (the one that
  drains the fleet to zero) returned Nil instead of `true`,
  so Invaders' orchestrator never saw the wave-clear signal,
  the score stalled at 540 instead of 550, and `$WaveComplete`
  never fired.

### Minimal reproducer

```frame
@@[target("gdscript")]

@@system Repro : RefCounted {
    interface:
        do_thing(use_inner: bool): bool

    machine:
        $A {
            do_thing(use_inner: bool): bool {
                if use_inner:
                    if true:
                        -> $B
                    @@:(true)
                @@:(false)
            }
        }
        $B { }
}
```

### Observed generated GDScript

```gdscript
func _s_A_hdl_user_do_thing(__e, compartment):
    var use_inner = __e._parameters[0]
    if use_inner:
        if true:
            var __compartment = self.__prepareEnter("B", [], [])
            self.__transition(__compartment)
            return                              # <-- BARE return!
        self._context_stack[-1]._return = true  # <-- dead branch
    else:
        self._context_stack[-1]._return = false
```

When `use_inner` is true, control enters the inner `if true`,
transitions to `$B`, and bare-returns. `_return` is never set,
so the function returns `Nil`. The `@@:(true)` outside the
inner `if` (intended as the fall-through value when the inner
`if` is *false*, but here the inner if is unconditionally true
so it should be the return path) gets generated *unreachable*.

### Expected generated GDScript

The `@@:(true)` should become `_return = true` *before* the
transition, OR the bare `return` should be replaced with one
that picks up the implicit fall-through value. Specifically:

```gdscript
if use_inner:
    if true:
        var __compartment = self.__prepareEnter("B", [], [])
        self.__transition(__compartment)
        self._context_stack[-1]._return = true   # set first
        return
    self._context_stack[-1]._return = true
else:
    self._context_stack[-1]._return = false
```

The semantics in Frame are: a transition `-> $X` does not
short-circuit the surrounding control flow; the rest of the
event handler runs. The generator already gets this right when
the `@@:(value)` is *inside* the same branch as the transition,
or when the transition is the only statement in the branch and
the `@@:(value)` follows it (the `EggsIncantation.$WaitingFoo`
case after our workaround). The defect is specific to the
*nested-if* shape where the transition is two levels deep and
the return value is one level out.

### Workaround in this repo

In every branch that contains a transition, add an explicit
`@@:return(value)` so the generator emits the return value at
each transition site rather than relying on a fall-through
`@@:(value)` later in the body:

```frame
do_thing(use_inner: bool): bool {
    if use_inner:
        if true:
            -> $B
            @@:return(true)        # explicit at transition site
        @@:return(true)            # explicit even in fall-through
    @@:(false)
}
```

This generates correctly. The downside is duplicating the
return value; there's no clean way to factor it.

### Notes for triage

- This is the same family as Issue #1 (the May 3 paren-drop)
  and the EggsIncantation Nil-return — all involve transitions
  interacting awkwardly with the generator's return-value
  emission. The pattern across all three: framec's per-event
  return-handling logic doesn't always survive a transition
  inside the body.
- The fix is presumably in the same area of the codegen.
  Adding test coverage for "transition inside nested control
  flow + fall-through @@:(value)" would catch this family of
  issue going forward.

---

## Appendix: working features I lean on heavily and didn't re-verify

For completeness — these all worked first-try and aren't bugs;
listing so the maintainer knows the surface area I've exercised:

- HSM with `=>` parent-state inheritance (Stealth `$Aware`,
  Asteroids `$InGame`, Lamp `$On`).
- State stack `push$` / `-> pop$` (Asteroids hyperspace, Stealth
  investigate, $InGame.pause).
- Parameterized systems with constructor args + defaults
  (Asteroids' `difficulty`, Dwarves' `seed`).
- Composition: `domain: foo = @@Foo()` with auto `@@[persist]`
  recursion via `bytes_to_var(self.foo.save_state())`.
- Operations block + `@@[save]` / `@@[load]` placeholders.
- State variables (`$.timer`) surviving `push$` and not surviving
  normal transitions; preserved across `@@[persist]` round-trips.
- `@@:return(value)` and `@@:(value)` with bare values, locals,
  and dictionaries.
- `@@:return({"key": val, ...})` — Dictionary literals work fine.
- Multi-element Array operations on `domain` Arrays
  (`asteroids.append({...})`, `listeners.sort_custom(...)`).

The persist runtime (compartment serialization, state stack
serialization, named domain field traversal) is rock solid for
the patterns I've used.
