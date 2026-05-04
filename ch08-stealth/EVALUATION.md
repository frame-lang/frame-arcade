# Stealth: an honest evaluation

**Question:** Is Frame a credible alternative to behavior trees
for agent AI?

**TL;DR:** Frame is **a 5/5 win for Stealth** — and the chapter
makes a specific architectural argument: behavior trees solve
the "lots of leaf behaviors with shared decorators" problem, but
HSM+state-stack solves the same problem in a different shape
that's often clearer for game agents. The Guard FSM has `$Aware`
as a parent state owning the shared "did I just see the player?"
handler ($Patrolling, $Investigating, $Searching all inherit it),
and `hear_sound` pushes the current state onto a stack so the
guard can investigate-then-resume. Three guards in the maze, each
parameterized by patrol route, all share the FSM.

This is also the first chapter to use `@@[persist]` for save/
restore — the cabinet variant doesn't add it (Stealth's chapter
source uses it directly).

---

## What was built

- `Guard` — 6 states ($Idle / $Patrolling / $Investigating /
  $Searching / $Alerted / $Engaged) with `$Aware` HSM parent
  for $Patrolling/$Investigating/$Searching. State stack on
  hear_sound. `@@[persist]` round-trips state + patrol route.
- `Stealth` — orchestrator with $Attract / $Playing / $Caught /
  $Escaped lifecycle.

**Frame source:** ~590 lines
**Generated GDScript:** ~2000 lines
**Driver:** ~830 lines (maze, FOV cones, line-of-sight, render)
**Smoke tests:** 29 checks covering Guard lifecycle, $Aware HSM
shared spot_player, hear_sound push/pop, save/restore.

---

## Per-system Frame value scoring

| System | Score | Why |
|---|---|---|
| `Guard` | **5** | $Aware is the BT-decorator analogue — a single condition ("did I just see the player?") expressed once, applied to every relevant child state. Plus the hear_sound state stack (push current state, run $Investigating, pop back) — same pattern as Pac-Man's frighten but applied to per-agent investigation. The shape genuinely competes with behavior trees on legibility for this problem. |
| `Stealth` | **3** | Four-state lifecycle orchestrator that wraps the three guards. Standard orchestrator shape; nothing novel for the chapter's pedagogical thesis. |

---

## What Frame demonstrably did well

### 1. $Aware as a behavior-tree decorator analogue

In a behavior tree, you'd have a "Spot Player" condition node
attached as a decorator to multiple sub-trees (patrol, investigate,
search). In Frame, you have `$Aware` as a parent state that owns
the `spot_player` handler; $Patrolling, $Investigating,
$Searching all `=> $^` to inherit it. The architectural shape is
isomorphic; the Frame version is *closer to the source code*
(no separate BT data file, no separate BT runtime).

### 2. State stack for "investigate then resume"

When a guard hears a sound, they push their current patrol/search
state and go to $Investigating. When the investigation expires,
they pop back to where they were. The patrol's route progress
(next_wp, last_known) is preserved automatically via push$
compartment serialization.

A behavior tree would model this with a "high-priority
interruption" node and a stack of suspended sub-trees. The Frame
push$/pop$ is the same idea expressed differently.

### 3. Three guards × parameterized + saved together

`@@[persist]` traverses the named domain fields (guard1, guard2,
guard3) and recursively saves each guard's compartment + state
variables + patrol Array. Save mid-investigation, restore — every
guard resumes exactly where it was, including pushed compartments.

This is the chapter that proves Frame's persistence story works
for agent AI specifically. CCA proves it for IF; Stealth proves
it for action games.

---

## What Frame demonstrably *didn't* help with

### 1. Vision-cone + line-of-sight checks

The driver computes per-frame whether each guard can see the
player (FOV angle + raycast through the maze tiles). The FSM
fires `spot_player(at)` while the player is visible; when the
player slips out of sight, the events stop arriving. The FSM
doesn't know about geometry.

### 2. Pathfinding

The driver implements A* (or simpler grid-walking) to move guards
toward `get_target()`. Frame just exposes "I want to be at this
Vector2"; the driver figures out how.

### 3. Maze representation

Tile grid, walls, corridors — driver-side. The FSM doesn't know
the maze topology.

---

## Comparison: hypothetical Stealth in plain GDScript or BT

### Plain GDScript

```gdscript
class Guard:
    var state: int  # PATROLLING, INVESTIGATING, ...
    var pre_invest_state: int = -1

    func spot_player(at):
        # Have to remember to handle this in every relevant state!
        if state in [PATROLLING, INVESTIGATING, SEARCHING]:
            last_known = at
            state = ALERTED
```

The `state in [list]` check is the BT-decorator written manually.
Easy to forget when a 4th relevant state is added.

### Behavior tree

```
Selector (root)
├── ConditionDecorator (can_see_player)
│   └── Sequence (chase)
└── Selector (idle behaviors)
    ├── Patrol
    ├── Investigate
    └── Search
```

The decorator is explicit, applied to the top of the
"chase" branch, sees-player condition queried each tick. Works,
but you've now added a BT runtime + a BT authoring format to
your project.

### Frame

```frame
$Aware {
    spot_player(at: Vector2) {
        self.last_known = at
        -> $Alerted
    }
}

$Patrolling => $Aware { ... }
$Investigating => $Aware { ... }
$Searching => $Aware { ... }
```

Same intent as the BT, expressed in code. No separate runtime.
No separate authoring tool. Just FSM + HSM.

---

## When to reach for Frame for a Stealth-class game

**Use Frame when:**
- Agents have shared "interrupt" behaviors (see-player, hear-
  sound, take-damage) that need to apply across multiple states.
- The interrupt needs to remember context (where I was) and
  resume after the interrupt clears.
- You want save/restore that round-trips agent state including
  pushed compartments.

**Use a behavior tree when:**
- Designers (non-programmers) need to author AI behaviors.
- The agent's behavior tree is highly data-driven and changes
  frequently without code changes.
- Existing BT tooling (visual editor, debugger) is part of your
  pipeline.

**Don't reach for either when:**
- The agent has 2 modes only.
- The "interrupt" doesn't need to resume the prior behavior.

For Stealth (programmer-authored, save/restore needed, agent
behavior is intrinsic to the game design rather than tunable
content): Frame wins clearly.
