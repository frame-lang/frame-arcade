# Chapter 8 — Stealth

A 2D top-down stealth game in a maze, three patrolling guards, vision
cones the player can see, line-of-sight against the maze grid. Reach
the green exit without entering a guard's cone.

This chapter is the book's answer to the question game programmers
ask most when they hear "state machine" applied to game AI:

> *"OK but doesn't everyone use behavior trees for this?"*

Yes — and after you finish this chapter you'll have a working
stealth AI built in Frame, plus a clear sense of when an HSM beats a
BT and when a BT beats an HSM. Both sides get a fair hearing in the
last section.

## What This Chapter Teaches

- **Parameterized systems with multiple instances** — three guards
  that share one `@@system Guard` definition, instantiated three
  times by the top-level `Stealth` system, each handed a different
  patrol route at `init()`. (Same shape as Pac-Man's parameterized
  ghosts in chapter 5; here we lean on it harder.)
- **The state stack for interrupt-and-resume** — `push$` /
  `-> pop$` on the patrol→investigate→patrol cycle. A guard who
  hears something pushes their patrol state, transitions to
  `$Investigating`, runs a timer, then pops back exactly where they
  left off — `next_wp` cursor and all.
- **HSM parent inheritance as a "decorator-without-decorator"** —
  the `$Aware` parent state defines a single `spot_player` handler
  that every child state ($Patrolling, $Investigating, $Searching)
  inherits. `$Alerted` overrides the handler to stay in $Alerted
  while refreshing memory. Compare to a BT, where this is typically
  a condition-decorator wrapping every leaf or the same condition
  copy-pasted at every relevant node.
- **The "brain / body" split, doubled** — Frame owns each guard's
  mind (state, target, last-known-position, timers); the driver
  owns the world's geometry (positions, vision cones,
  line-of-sight against the maze grid, collision). Same lesson as
  chapter 4 but with multiple coordinated minds.
- **Frame vs behavior trees, candidly** — included at the end so
  it doesn't dominate the chapter. Bring your own opinions.

## Running It

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

**Controls:**

| Key | Action |
|-----|--------|
| ↑ ↓ ← → (or W A S D) | Move |
| Esc | Quit |

The exit is the green pulsing tile in the bottom-right. The yellow
running figure is you. The pale-blue circles with vision cones are
guards. Cones turn yellow when a guard becomes suspicious and red
when they're alerted (chasing).

## The Two Systems

```
┌────────────────────────────────────────────┐
│  Stealth                              @@[main]
│  $Attract → $Playing → $Caught/$Escaped    │
│                                            │
│  domain:                                   │
│    guard1 = @@Guard()  ── handed patrol[0] │
│    guard2 = @@Guard()  ── handed patrol[1] │
│    guard3 = @@Guard()  ── handed patrol[2] │
│    elapsed: float                          │
│    caught_by: int                          │
└────────────────────────────────────────────┘

┌────────────────────────────────────────────┐
│  Guard                                     │
│  $Idle                                     │
│  $Aware ───── HSM parent ──────┐           │
│    $Patrolling => $Aware ◄── push$ ────┐   │
│    $Investigating => $Aware ── pop$ ───┘   │
│    $Alerted => $Aware                      │
│    $Searching => $Aware                    │
│  $Engaged                                  │
│                                            │
│  domain:                                   │
│    patrol: Array  (Vector2 waypoints)      │
│    next_wp: int                            │
│    target: Vector2                         │
│    last_known: Vector2                     │
│    speed: float                            │
└────────────────────────────────────────────┘
```

Two systems and the world. The stealth system is small (it's an
orchestrator); the interesting one is `Guard`.

## Parameterized Systems with Multiple Instances

Open [`frame/stealth.fgd`](./frame/stealth.fgd) and find the Stealth
system's domain block:

```frame
domain:
    guard1 = @@Guard()
    guard2 = @@Guard()
    guard3 = @@Guard()
```

Three Frame systems composed into the parent. The Pac-Man chapter
hinted at this; here it's load-bearing. There's no "guard class
hierarchy" — every guard is the same code with different *data*
(the patrol route handed in at `init()`).

```frame
$Attract.start(p1: Array, p2: Array, p3: Array) {
    self.guard1.init(p1, self.PATROL_SPEED)
    self.guard2.init(p2, self.PATROL_SPEED)
    self.guard3.init(p3, self.PATROL_SPEED)
    -> $Playing
}
```

The driver passes the three routes (it owns the maze, so it owns
the patrol design). Each guard gets its identity from its route.

In a behavior-tree version of this, you'd typically have a Guard
*template* tree shared by all three agents, with per-agent local
state stored on a "blackboard." The Frame version's parameterized
system + per-instance domain plays that role with first-class
language support — no blackboard pattern, no template
instantiation, just three `@@Guard()` calls.

Want twelve guards? Move them into an array (`guards: Array`) and
dispatch in a loop. This chapter uses three named fields for
readability of the chapter prose, but the pattern scales.

## The State Stack: Patrol Interrupted by Investigation

Find `$Patrolling`:

```frame
$Patrolling => $Aware {
    tick(dt: float, current_pos: Vector2) {
        if self.patrol.size() == 0:
            return
        if current_pos.distance_to(self.target) < self.ARRIVAL_RADIUS:
            self.next_wp = (self.next_wp + 1) % self.patrol.size()
            self.target = self.patrol[self.next_wp]
    }

    hear_sound(at: Vector2) {
        push$
        self.last_known = at
        -> $Investigating
    }
    ...
}
```

`hear_sound` does **`push$`** before transitioning. The current
compartment of `$Patrolling` — its identity *plus the value of any
state variable* — is saved onto the state stack.

Then `$Investigating`:

```frame
$Investigating => $Aware {
    $.timer: float = 0.0

    tick(dt: float, current_pos: Vector2) {
        $.timer = $.timer + dt
        if $.timer >= self.INVESTIGATE_DURATION:
            -> pop$
    }
    ...
}
```

`-> pop$` is the inverse of `push$`. The pushed `$Patrolling`
compartment is restored. `next_wp`, the partial progress along the
current segment, and any other state vars come back exactly as they
were.

### Why this is hard without a state stack

In a BT version, "interrupt patrol to investigate, then resume" is
typically expressed as a Sequence node containing the patrol
behavior, with a Selector higher up that *can* short-circuit to an
investigation subtree. When investigation ends (returns Success),
control returns up the tree and the Selector re-evaluates. Whether
patrol resumes from where it left off or restarts depends on
whether the Sequence remembered its child cursor.

Many BT implementations *don't* preserve cursor on re-entry by
default — you have to opt in (a "running" status, persistent
sub-state, etc.). The state stack pattern makes resumption the
default, with no extra bookkeeping.

This isn't an inherent BT weakness; well-engineered BT frameworks
handle it. But "what state was this child node in when we left?"
is *implicit* in BTs and *explicit* in Frame. Explicit beats
implicit when you're trying to reason about correctness.

### Which state vars actually survive

A subtle point worth pausing on. **`push$` saves state variables
(`$.timer`, `$.foo`, etc.). It does NOT save domain variables
(`self.patrol`, `self.target`, etc.).** Those are persistent across
all states in a system; pushing/popping them would be incorrect.

This had a real consequence in the cabinet variant of this
chapter (which adds `@@[persist]`): an early version of
`$Investigating` had a `$>()` enter handler that did
`self.target = self.last_known`. That looks innocent, but `target`
is a *domain* variable. Setting it during investigation
permanently changed the patrol target — `pop$` couldn't undo it
because the state stack doesn't track domain. The fix was to NOT
touch `self.target` in `$Investigating`, gate movement with a
`should_move()` query that returns false there, and let the patrol
target survive the round-trip naturally.

Lesson: when a state's behavior is "pause this thing and come
back to it later," anything you write while paused had better be
in `$.X` state variables, not domain.

## HSM Parent Inheritance

Find `$Aware`:

```frame
$Aware {
    spot_player(at: Vector2) {
        self.last_known = at
        -> $Alerted
    }

    touched_player() {
        -> $Engaged
    }
    ...
}
```

And the children:

```frame
$Patrolling => $Aware { ... }
$Investigating => $Aware { ... }
$Searching => $Aware { ... }
$Alerted => $Aware {
    spot_player(at: Vector2) {
        // Override — already alerted, don't re-transition.
        self.last_known = at
    }
    ...
}
```

`$Patrolling`, `$Investigating`, and `$Searching` all inherit
`$Aware`'s `spot_player` handler. Seeing the player from any of
these three transitions to `$Alerted`. `$Alerted` itself overrides
the handler to refresh memory without re-transitioning (you don't
want a hard reset every time you re-glimpse the player you're
already chasing).

Four states, one shared "spot the player" behavior, declared once.

### What this would look like in a BT

In a BT, the same logic is typically expressed as a high-priority
condition node:

```
Selector (root)
  ├─ Sequence
  │   ├─ Condition: can_see_player
  │   └─ Action: chase
  ├─ Sequence
  │   ├─ Condition: heard_sound
  │   └─ Action: investigate
  └─ Action: patrol
```

The "can_see_player" condition is checked first every tick, so any
behavior below it (investigate, patrol) is preempted when the
player is visible. That works, and it's idiomatic.

The HSM version isn't *better* — it's just different. The HSM
expresses "I'm in this mode, and modes can have parents that
share behavior." The BT expresses "I evaluate priorities top-down
every tick, and high-priority conditions preempt everything
below."

Both can express the patrol-investigate-chase pattern correctly.
The HSM tends to read as *what state am I in*; the BT tends to
read as *what action gets the highest priority right now*. For
agents whose modes have meaningful internal state (timers,
counters, cursors), the HSM's explicit state semantics make
debugging easier. For agents whose decisions are mostly stateless
priority pickers, BTs are cleaner.

## Brain / Body Split, Doubled

Following the pattern from chapter 4, Frame owns the agent's mind
and the driver owns the geometry:

| Frame owns | Driver owns |
|---|---|
| Each guard's state ($Patrolling/$Alerted/etc.) | Each guard's actual `pos: Vector2` |
| `target: Vector2` (where the guard wants to walk) | Movement integration + collision against maze grid |
| `last_known: Vector2` (player memory) | Vision cone math, line-of-sight ray-march |
| `patrol`, `next_wp` (route state) | Patrol *layout* — which cells form each route |
| Timers ($.timer in Investigating/Searching) | Frame-rate, ticks |
| `should_move()` query | Whether to advance the guard's pos this frame |

The driver each frame:

1. Moves the guard's actual position toward `guard.get_target()`,
   gated on `guard.should_move()`.
2. Computes "can guard *i* see player?" via vision cone + LOS.
3. If yes, fires `guard.spot_player(player_pos)`. Otherwise
   says nothing.
4. Calls `fsm.tick(dt, ...)` to advance Frame logic.

The Frame side never touches a Vector2 it didn't get from the
driver. The driver never decides whether to chase. The boundary is
clean.

## Honest Limitations

Two warts in this chapter worth naming.

### No pathfinding

Guards in `$Alerted` walk *straight-line* toward `last_known`. If
a wall is in the way, the driver's slide-against-wall collision
nudges them along, but they have no plan for "go around the
corner." A guard can absolutely get wedged trying to reach a
position behind a wall.

The fix in this chapter is **temporal, not spatial**: a
`CHASE_TIMEOUT` of 4 seconds in `$Alerted`. If the guard hasn't
reached `last_known` in that time, they give up and transition to
`$Searching`. They don't navigate cleverly; they just bound the
worst case.

Adding A* would be a real chunk of code (priority queue, grid
expansion, path caching) and would compete with the chapter's
pedagogy. The exercise is left at the end; the chapter's lesson
is "simple state machines with explicit timeouts beat clever
fragile heuristics."

### Patrol routes are corridors, not topology

Each guard's route is a list of waypoints chosen by hand to lie
inside one of the maze's open corridors. Routes that cross walls
would wedge guards just like alerted chases would. A real game
would generate routes from the maze topology so the level designer
can't accidentally place a waypoint inside a wall.

## Frame vs Behavior Trees

Now the comparison piece. **TL;DR: HSMs and BTs solve overlapping
problems with different ergonomics. The choice depends on what
your AI's hardest property is.**

### Where Frame's HSM beats BTs

- **State queryability.** `guard.is_alerted()` returns immediately,
  reading the state name. BTs typically expose state via blackboard
  variables that the running tree has to remember to update. The
  state *is* the answer in an HSM; the state is *derivable* from
  blackboard reads in a BT.
- **The state stack as first-class subroutine call.** push/pop with
  state-variable preservation is the right primitive for
  "interrupt and resume." BTs handle this with "running" status
  and re-entry semantics that vary by framework.
- **Persistence is intrinsic.** When `@@[persist]` lands on the
  cabinet variant of this chapter, the entire FSM tree round-trips
  in one `save_state()` call — current state, pushed compartments,
  every state var. BTs need explicit "what node was running with
  what local state" save logic.
- **Smaller surface area.** HSMs have fewer concepts than BTs (no
  decorators, no parallel nodes, no "blackboard" pattern). For
  most agent AI of intermediate complexity, simpler.

### Where BTs beat Frame's HSM

- **Visual editors are richer.** Behavior Designer, Unreal's BT
  editor, Godot's various BT plugins — the tooling for
  non-programmer authoring of BTs is significantly better than for
  HSMs. If your designers want to compose AI graphically, BT
  ecosystems have a head start.
- **Composition across agents is easier.** A reusable
  "FleeFromFire" subtree drops into any agent's BT. The Frame
  equivalent is a parameterized system, which is heavier to set up
  for an "ability you can grant to any character."
- **Reactive priority is the BT's default.** "Always do the
  highest-priority thing that's possible right now" is what a
  Selector with conditions expresses naturally. The HSM version
  needs explicit transitions on every parent state.

### When to pick which

- Pick HSM (Frame) when: agent's modes have meaningful internal
  state (timers, counters, cursors), persistence matters,
  programmer authoring, intermediate complexity (5–30 modes total
  per agent).
- Pick BT when: visual authoring, ability composition across many
  agent types, mostly-stateless priority decisions, framework-
  ecosystem already in place.
- For very simple agents, both are fine. The win shows up at
  intermediate complexity.

A small confession: this book's chapter exists because the author
believes Frame's HSM is *underrated* for agent AI specifically.
The BTs-as-default trend in mainstream game dev came from a few
high-profile titles (Halo 2, then everyone) and a generation of
GDC talks. It's not wrong; it's also not the only good answer.
This chapter is one data point that the alternative still works.

## Exercises

**1. Add A* pathfinding to alerted chases.** Replace the chase
timeout with real path planning. The Guard FSM doesn't need to
know — pathfinding lives in the driver, computing a series of
waypoints from current position to `last_known`. Frame's `target`
becomes "next waypoint on the planned path" rather than
`last_known` directly.

**2. Add a sound mechanic.** The driver detects when the player
moves fast (held shift, say) within range of a guard, and fires
`guard.hear_sound(player_pos)`. The guard pushes patrol and
investigates. The state-stack code is already there; only the
driver-side detection is new.

**3. Player can hide.** Add a "hide spot" cell type to the maze
(behind a barrel, in a closet). When the player is in a hide
spot, the LOS check fails even within the cone. Guards mid-chase
will reach `last_known` (now empty) and go to $Searching. After
$Searching ends, they patrol back. Player escapes.

**4. Guard radio.** When one guard becomes alerted, all guards
within "radio range" are notified — they get `last_known` set and
transition to `$Alerted` on their next tick. Do this without
modifying Guard's interface: add a `notify_alert(at)` event the
driver fires on the affected guards.

**5. Patrol from maze topology.** Write a maze-aware route
generator. Given an open region of the maze, produce a patrol
loop that visits its boundary or walks a Hamiltonian-ish path
through it. Eliminates the hand-placement of waypoints.

**6. The "sleeper" guard.** Add a fourth guard who starts in
`$Idle` and only initializes (transitions to $Patrolling) when
some condition is met — say, the player has been spotted at
least once by another guard. Demonstrates conditional aspect-like
activation; sets up nicely for chapter 9 if/when it comes.

## What's Next

The cabinet variant of this chapter (in `arcade/godot/scripts/`)
will add `@@[persist]` to the entire Stealth tree and let the
player save mid-chase. Same architectural lesson as
asteroids-in-the-cabinet: the state stack survives serialization,
so a saved game restores into the exact pushed compartment with
the right `next_wp` cursor and timer. We're not adding it to the
chapter source so the chapter stays focused on agent AI; the
cabinet has it as a feature.

If you want a deeper take on multi-agent coordination, behavior
selection at scale, and full cross-cutting concerns
(darkness/inventory/timers as their own state machines), that's
the territory the next chapter would explore — possibly building
toward a much larger system where dozens of small FSMs run in
choreographed coordination. But this is where Chapter 8 ends.
