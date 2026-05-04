# Pac-Man Ghost AI: an honest evaluation

**Question:** Does Frame model ghost AI better than the
canonical "behavior tree" or "match-based personality" approach
classic Pac-Man clones use?

**TL;DR:** Frame is **a 5/5 win for Pac-Man** — the showpiece
chapter. The Ghost FSM with `$InPen / $OutOfPen` HSM parents +
a state-stack push to `$Frightened` (so each ghost remembers
whether it was scattering or chasing before the power pellet)
is the cleanest expression of ghost AI I've seen. Four ghosts
share the FSM; their personalities (target_kind parameter)
diverge through the parameterized-system pattern. The two-stack
coordination — global game phase pushing into Frightened, each
ghost individually pushing into Frightened — is the chapter's
big architectural idea and works exactly as it should.

---

## What was built

- `Ghost(name, home_corner, target_kind)` — 5 states with HSM
  parents and state-stack push to Frightened. Parameterized × 4
  ghosts (Blinky, Pinky, Inky, Clyde).
- `GhostPen` — single-state release scheduler (timer + index).
- `GhostGame` — orchestrator with 4 phases: $Idle / $Scatter /
  $Chase / $Frightened (pushed). Drives global scatter↔chase
  cycle and frighten timer.

**Frame source:** ~570 lines
**Generated GDScript:** ~2000 lines
**Driver:** ~830 lines
**Smoke tests:** 39 checks covering Ghost HSM + state stack,
parameterized × 4 ghosts, GhostPen scheduling, GhostGame
phase transitions and frighten cycle.

---

## Per-system Frame value scoring

| System | Score | Why |
|---|---|---|
| `Ghost` | **5** | $InPen vs $OutOfPen as HSM parents share `power_pellet_eaten` (which pushes to $Frightened) only on the out-of-pen children. $Chase and $Scatter both inherit from $OutOfPen. The push$/pop$ mechanism means each ghost individually remembers which phase it was in before the pellet, and pops back to it when the frighten expires — without a per-ghost `pre_frighten_phase` variable. Five distinct states + clean parent inheritance + state-stack push for the interrupt. The pattern's peak. |
| `GhostPen` | **2** | Single state, three operations, one timer. Frame ceremony for what would be a 30-line helper class. The chapter keeps it as a `@@system` for compositional consistency (it's a peer of Ghost in GhostGame's domain), not because the FSM scaffolding earns its keep. Reasonable trade-off. |
| `GhostGame` | **5** | The orchestrator that drives the phase cycle, broadcasts frighten, releases ghosts on schedule, and holds the score. `$Frightened` is itself pushed onto $Scatter or $Chase — same state-stack pattern, applied at the global level. On `<$()` (about-to-pop), it broadcasts frighten_expired to every ghost so they all pop in sync. The exit handler at the broadcast moment is the right place — guaranteed to fire exactly once before the pop completes. |

---

## What Frame demonstrably did well

### 1. Two-level state stack: global game + per-ghost

When the player eats a power pellet:

1. `GhostGame.power_pellet_picked_up()` pushes the global game
   from $Scatter/$Chase to $Frightened.
2. The global $Frightened entry calls `_broadcast_frighten()`,
   which calls `power_pellet_eaten()` on every ghost.
3. Each ghost's $Chase or $Scatter handles `power_pellet_eaten`
   by pushing to its own $Frightened.

When the timer expires:

1. `GhostGame.$Frightened.<$()` (exit handler) calls
   `_broadcast_frighten_expired()`, which calls
   `frighten_expired()` on every ghost.
2. Each ghost's $Frightened pops back to its pre-pellet phase.
3. `GhostGame` itself pops back to $Scatter or $Chase (whichever
   was active before).

Two stacks, perfectly coordinated by the orchestrator broadcast
+ exit handler. Replicating this in plain GDScript without bugs
is genuinely hard.

### 2. Parameterized × 4 with divergent personalities

`Ghost(name, home_corner, target_kind)`. Each ghost has the same
state machine but different home corners (where they go in
$Scatter) and different target_kind (which the driver uses to
compute $Chase target — Blinky chases Pac-Man directly, Pinky
ambushes 4 tiles ahead, Inky uses Blinky's position, Clyde
retreats when close). The FSM is shared; the personalities are
parameters.

### 3. Eaten ghosts return as eyes

`$Frightened.eaten() -> $Eaten`. `$Eaten` is the "eyes returning
to the pen" state — not dangerous, not edible, can't be eaten
again. `arrived_at_pen() -> $InPen` returns the ghost to the
pen for re-release. The terminal `$Dead` state from Invaders
becomes a transient `$Eaten` here because the ghost is going to
respawn.

---

## What Frame demonstrably *didn't* help with

### 1. Pathfinding

The driver computes ghost movement targets each frame from
`get_target_kind()` and Pac-Man's position. The FSM tells the
driver "you are dangerous and your home corner is X, target_kind
is 2 (means: 4 tiles ahead of player)" — pathfinding logic is
the driver's job.

### 2. Maze representation

The maze is a tile grid in the driver. The FSM doesn't know
about walls, dots, or the maze topology. Correct division.

---

## Comparison: hypothetical Pac-Man in plain GDScript

The two-stack frighten/pop coordination is where Frame earns its
keep over plain GDScript:

```gdscript
# Plain GDScript — error-prone
var pre_frighten_phase: int  # per ghost
var global_pre_frighten: int

func eat_power_pellet():
    global_pre_frighten = global_phase
    global_phase = PHASE_FRIGHTENED
    for g in ghosts:
        g.pre_frighten_phase = g.phase
        g.phase = GHOST_FRIGHTENED

func frighten_expired():
    global_phase = global_pre_frighten
    for g in ghosts:
        if g.phase == GHOST_FRIGHTENED:
            g.phase = g.pre_frighten_phase
        # Watch out — what if a ghost was eaten during frighten?
        # What if frighten was triggered while one ghost was being
        # eaten? The 'pre_frighten_phase' fields require careful
        # discipline.
```

vs.

```frame
# Frame
$Chase {
    power_pellet_eaten() {
        push$
        -> $Frightened
    }
}
# ... and pop$ does the right thing automatically.
```

The Frame version makes the bug class go away. push$ saves the
*entire* compartment (state + state variables + local data); pop$
restores it. There is no `pre_frighten_phase` field to forget to
update on a corner case.

---

## When to reach for Frame for a Pac-Man-class game

**Use Frame when:**
- You have multiple agents that share an AI but differ by
  parameter.
- An "interrupt" mechanic (frightened, stunned, charmed, paused)
  needs to remember per-agent context.
- The interrupt needs to be coordinated globally (everybody flees
  on power-pellet) AND per-agent (each ghost was in a different
  phase before it).

**Don't reach for Frame when:**
- The agent has 2 modes only and no shared interrupt logic.
- The "interrupt" is a single boolean that affects everyone the
  same way.

For Pac-Man: absolutely. This is the chapter where Frame's value
proposition is most visible.
