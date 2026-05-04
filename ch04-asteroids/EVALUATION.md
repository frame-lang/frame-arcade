# Asteroids: an honest evaluation

**Question:** Does the state-stack (`push$ / pop$`) earn its
complexity for hyperspace, or could a transient flag carry it?

**TL;DR:** Frame is **a 4/5 win for Asteroids**, mostly thanks
to the state stack. The Ship's hyperspace is canonically a
"step out of normal play, run a sub-state, come back exactly
where you were" flow — and `push$ → -> $InHyperspace → ->
pop$` is the textbook expression of that. Plain GDScript would
need a `pre_hyperspace_state` instance var; the Frame version
preserves the state including all its state variables for free.

The chapter is also the introduction of parameterized systems
with `Asteroids(difficulty: int = 2)`, which the cabinet variant
(arcade/frame/asteroids.fgd) layers `@@[persist]` over without
modifying the chapter source.

---

## What was built

- `Ship` — 5 states with state-stack hyperspace.
- `AsteroidField` — single-state container with split-into-children
  rules.
- `Asteroids` — top-level HSM ($InGame parent) parameterized by
  difficulty.

**Frame source:** ~590 lines
**Generated GDScript:** ~1900 lines
**Driver:** ~640 lines
**Smoke tests:** 43 checks covering Ship lifecycle, hyperspace
push/pop, AsteroidField split chain, parameterized difficulty,
HSM pause/resume.

---

## Per-system Frame value scoring

| System | Score | Why |
|---|---|---|
| `Ship` | **5** | The state-stack hyperspace is the pattern's clearest small example. `$Alive.hyperspace()` does `push$; -> $InHyperspace`. `$InHyperspace.tick()` decrements timer and `-> pop$` when expired. The ship's lives counter, position-via-driver, all preserved automatically. Adding "small chance of dying in hyperspace" is one branch in the pop logic — the chapter's exercise section actually suggests this as a follow-up. |
| `AsteroidField` | **3** | Single-state container around an Array of dicts. The split-into-children logic (size 3 → 2x size 2 → 2x size 1 → none) lives in actions. The system gives you a clean interface but the FSM scaffolding is mostly ceremony — same trade-off as Breakout's `BrickField`. |
| `Asteroids` | **4** | Top-level HSM with `$InGame` parent. Parameterized by `difficulty: int = 2`; the param affects starting wave size and points-per-hit multiplier. Difficulty as a Frame system parameter is the cleanest spelling for "this system has a config knob"; the alternative is a setter or a constructor arg in plain GDScript, both fine but slightly less self-documenting. |

---

## What Frame demonstrably did well

### 1. State stack as proper subroutine

`push$ → -> $X → ... → -> pop$` is genuinely a subroutine call
in state-machine form. Domain variables persist; state variables
of the pushed state are freshly initialized; on pop, you're back
exactly where you started. The Asteroids hyperspace is the
clearest small demo of this pattern in the book — Pac-Man (next
chapter) leans on it harder.

### 2. Difficulty as a system parameter

`@@system Asteroids(difficulty: int = 2)`, then
`Asteroids.new(3)` for hard mode. The difficulty value shows up
in domain initialization and in `_asteroids_for_wave()` /
`_size_points()` actions. Plain GDScript would have a
`difficulty: int = 2` instance var or a constructor arg —
equivalent, slightly less framed.

### 3. Asteroid splitting as data

The splitting rules (size 3 → 2x size 2, etc.) are a `while
sz > 1: spawn child(sz - 1)` loop. The state of the field
(positions, velocities, alive flags) lives entirely in the
domain Array, and the FSM's job is to expose the operations
(spawn_wave, split, advance, queries).

---

## What Frame demonstrably *didn't* help with

### 1. Asteroid physics

Drift, screen-wrap, collision detection — all driver-side. Frame
doesn't model continuous motion; the driver feeds `advance(dt,
court_size)` once per frame.

### 2. Random spawning

`_spawn_large` uses `randi()` and `randf()` for edge selection
and angle/speed jitter. There's no Frame benefit to randomness
itself; the system just owns the spawned-asteroid records.

---

## Comparison: hypothetical Asteroids in plain GDScript

The hyperspace mechanic in plain GDScript:

```gdscript
var pre_hyperspace_state: int = -1

func enter_hyperspace():
    pre_hyperspace_state = state
    state = STATE_HYPERSPACE
    timer = HYPERSPACE_DURATION

func _physics_process(dt):
    if state == STATE_HYPERSPACE:
        timer -= dt
        if timer <= 0:
            state = pre_hyperspace_state
            pre_hyperspace_state = -1
            x = randf_range(0, w)
            y = randf_range(0, h)
```

That's a "state stack of size 1 implemented manually." Frame's
push$/pop$ is the same thing but generalized: the stack can
arbitrarily nest (Pac-Man's frightened-mode stacks under
scatter-or-chase, and the same machine survives a save-mid-stack
in CCA's Endgame). The Asteroids version doesn't NEED the
generality, but having the pattern in the book before chapter 5
matters.

---

## When to reach for Frame for an Asteroids-class game

**Use Frame when:**
- A "step out and come back" mechanic exists (hyperspace,
  pause-with-context, mid-game dialog).
- You want save/restore that round-trips push-stacks correctly
  (cabinet variant adds @@[persist] for this).
- A configuration knob naturally maps to a system parameter.

**Don't reach for Frame when:**
- The "container of game objects" is your only state. Use a
  plain class or a Node group.
- The hyperspace flag is the only modal element. A boolean +
  timer is fine.

For Asteroids: yes — first chapter where push$/pop$ is the
right tool.
