# Chapter 5 — Pac-Man Ghost AI

Quick honesty up front: **this chapter isn't full Pac-Man.** It's the
*ghost AI* from Pac-Man, running in an open arena with a player you
can move around. No maze, no pellet dots, no extra lives — just the
four ghosts, four power pellets, and a Pac-Man you can drive into
them. Shipping the whole game would take another thirty pages on
maze generation, tile-based pathfinding, and lives/score
management, and none of that teaches Frame. The ghost AI does. That's
what we're here for.

The ghost AI is the most famous piece of game AI ever written, and
it's almost a pure state-machine problem. Every ghost has the same
five-mode state machine. They all respond to the same game events.
They only differ in their targeting rules and home corners. This is
the exact shape that **hierarchical state machines + parameterized
systems** were designed for. In Frame, four ghosts with distinct
personalities is about 200 lines of source.

## What This Chapter Teaches

- **HSM parent states with non-trivial inheritance** — `$OutOfPen`
  owns the power-pellet interrupt that `$Chase` and `$Scatter`
  both need. When a power pellet is eaten, both modes do the
  same thing, and the handler lives once.
- **Parameterized systems used for multiple instances** — one
  `@@system Ghost(name, home_corner, target_kind)` definition,
  four instances created by the driver.
- **Two state stacks interacting** — the game and each ghost each
  have their own state stack. A power pellet pushes on both
  simultaneously; the pellet expiring pops both back.
- **"Pure abstract" parent states** — `$OutOfPen` is never
  entered directly, only used as a container. Reinforces the
  pattern from chapter 3.

## Running It

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

**Controls:**

| Key | Action |
|-----|--------|
| Arrow keys (or WASD) | Move Pac-Man |
| R | Respawn the power pellets |

There's no death, no score loss, no restart — the game auto-starts
and runs forever. The HUD shows the current global phase (SCATTER /
CHASE / FRIGHTENED) and how much time is left on a frighten if one
is active.

**Things to watch for:**

1. Ghosts release from the pen one at a time, every 2 seconds.
2. After 7 seconds of scatter, they switch to chase. After 20
   seconds of chase, they switch back. The classic alternation.
3. Eat a power pellet. All four ghosts turn blue and flee toward
   the corner farthest from you. Frighten timer ticks down.
4. Catch a blue ghost. It turns into eyes (just two white dots)
   and heads back to the pen. When it arrives, it rejoins the
   normal rotation.
5. Watch the ghost personalities during chase. **Blinky** (red)
   heads straight at you. **Pinky** (pink) tries to get ahead of
   where you're going. **Inky** (cyan) flanks. **Clyde** (orange)
   is shy — chases when far, retreats when close.

Open `frame/pacman.fgd` alongside the game window. Every behavior
you see is expressed as a state transition.

## The Three Systems

```
┌────────────────────────────────────────────────────┐
│           GhostGame                                │
│  $Idle                                             │
│  $Scatter ──(timer)──▶ $Chase ◀──(timer)──┐        │
│     │                     │                │       │
│     │ push$         push$ │                │       │
│     ▼                     ▼                │       │
│  $Frightened ──(timer)──▶ pop$ ────────────┘       │
│                                                    │
│  domain:                                           │
│    ghosts: Array = []     ← populated by driver    │
│    pen = @@GhostPen()                              │
└────────────────────────────────────────────────────┘
             │
             │ owns and ticks
             ▼
┌──────────────────────────────────────────┐
│  Ghost(name, home, target_kind)  × 4     │
│                                          │
│  $InPen                                  │
│  $OutOfPen (HSM parent)                  │
│    ├── $Chase                            │
│    └── $Scatter                          │
│  $Frightened   ← pushed from chase/scat  │
│  $Eaten                                  │
└──────────────────────────────────────────┘
```

Four ghost instances all share one class definition. They differ
only in their constructor parameters. That's the win: when you add
a fifth ghost type later, you add zero states, zero handlers,
zero duplication — just another instantiation line in the driver.

## The Ghost State Machine, Walked Through

The whole thing is in [`frame/pacman.fgd`](./frame/pacman.fgd). Find
the Ghost system (line ~37).

### The shape

```
                  ┌──────────────┐
                  │   $InPen     │◀─────────────┐
                  └──────┬───────┘              │
                         │ released()           │
                         ▼                      │
                  ┌──────────────┐              │
                  │  $Scatter    │───┐          │
                  │   => $OutOf  │   │          │
                  │     Pen      │   │ phase    │
                  └──────┬───────┘   │ change   │
                         │ push$     │          │
                         ▼           ▼          │
     ┌───────────────────────┐ ┌──────────────┐ │
     │     $Frightened       │ │   $Chase     │ │
     │  (pushed, popped)     │ │   => $OutOf  │ │
     │                       │ │     Pen      │ │
     │       eaten()         │ └──────┬───────┘ │
     └──────────┬────────────┘        │         │
                ▼                     │         │
        ┌──────────────┐              │         │
        │   $Eaten     │              │         │
        │ (eyes → pen) │              │ reset   │
        └──────┬───────┘              └─────────┤
               │ arrived_at_pen()               │
               └────────────────────────────────┘
```

Five states (or six counting `$OutOfPen`, which is abstract).
Every arrow in this diagram is a real handler in the Frame source.
Compare that to the imperative version of Pac-Man ghost AI —
usually hundreds of lines of flag-juggling and nested switches.

### Why `$OutOfPen` is an HSM parent

Look at `$Chase` and `$Scatter`:

```frame
$Chase => $OutOfPen {
    phase_changed_to_scatter() {
        -> $Scatter
    }
    get_state(): String { @@:("chase") }
    => $^
}

$Scatter => $OutOfPen {
    phase_changed_to_chase() {
        -> $Chase
    }
    get_state(): String { @@:("scatter") }
    => $^
}
```

Each child handles only its own phase-change event and its own
`get_state()` override. *Everything else* — `power_pellet_eaten`,
`reset_to_pen`, and all the other queries (`get_name`, `is_dangerous`,
`is_edible`, etc.) — is defined once in `$OutOfPen`:

```frame
$OutOfPen {
    power_pellet_eaten() {
        push$
        -> $Frightened
    }
    reset_to_pen() {
        -> $InPen
    }
    get_state(): String         { @@:("out_of_pen") }
    get_name(): String          { @@:(self.gname) }
    get_home_corner(): Vector2  { @@:(self.home) }
    is_dangerous(): bool        { @@:(true) }
    is_edible(): bool           { @@:(false) }
    ...
}
```

Both child states inherit all of this via `=> $^`. If I wanted to
add a sixth global event — say `speed_boost_activated()` — I'd add
one handler in `$OutOfPen` and both children would get it for free.
This is exactly the kind of shared-cross-cutting-behavior that HSM
was built for, and Pac-Man is the textbook case.

### The power-pellet interrupt

When Pac-Man eats a power pellet, every ghost needs to be
interrupted — dropped out of whatever it was doing (chase or
scatter) and sent into frightened mode. When the pellet wears off,
they go **back to what they were doing**.

That "back to what they were doing" is what the state stack
expresses. `$OutOfPen` handles the event:

```frame
power_pellet_eaten() {
    push$
    -> $Frightened
}
```

`push$` saves the current compartment (the specific state — $Chase
or $Scatter — with all its state variables). `-> $Frightened`
transitions to frightened mode.

When the frighten timer expires, `$Frightened` does:

```frame
frighten_expired() {
    -> pop$
}
```

`-> pop$` restores the saved compartment. A ghost that was chasing
goes back to chasing; a ghost that was scattering goes back to
scattering. The state stack expressed "return to the phase you
were in" as a language primitive.

### The two-stack dance

Here's a subtle and wonderful thing. There are actually *two*
state stacks in play:

1. **GhostGame's state stack** — when `power_pellet_picked_up()`
   fires, the game itself pushes from `$Scatter` or `$Chase` onto
   `$Frightened`. The frighten timer ticks on the game.
2. **Each ghost's state stack** — the game then broadcasts
   `power_pellet_eaten()` to every ghost. Each ghost pushes its
   own `$Chase` or `$Scatter` onto its own `$Frightened`.

When the game's frighten timer expires:

```frame
$Frightened {
    <$() {
        # About to pop back. Tell every ghost to pop back too.
        self._broadcast_frighten_expired()
    }
    tick(dt: float) {
        ...
        if self.frighten_timer >= self.frighten_duration:
            -> pop$    # pops the GhostGame's own stack
    }
}
```

The exit handler fires *before* the pop. It broadcasts
`frighten_expired()` to every ghost, which each triggers
`-> pop$` on the ghost's own stack. Then the game's pop happens,
and we're back to chase or scatter — everywhere, in sync.

**That coordination between two independent state stacks is
exactly three handlers and a broadcast helper.** In imperative
code it's the kind of thing that takes a week to get right.

## The Four Ghosts, One System

The Ghost system declaration:

```frame
@@system Ghost(name: String, home_corner: Vector2, target_kind: int) : RefCounted {
    ...
    domain:
        gname: String = name
        home: Vector2 = home_corner
        tkind: int = target_kind
}
```

Three parameters, stored in domain variables. The driver
instantiates four ghosts with different values:

```gdscript
var GhostClass = PacManFSM.Ghost
var b = GhostClass.new("blinky", Vector2(court_size.x - 24, 24), 0)
var p = GhostClass.new("pinky",  Vector2(24, 24), 1)
var i = GhostClass.new("inky",   Vector2(court_size.x - 24, court_size.y - 24), 2)
var c = GhostClass.new("clyde",  Vector2(24, court_size.y - 24), 3)
fsm.add_ghost(b)
fsm.add_ghost(p)
fsm.add_ghost(i)
fsm.add_ghost(c)
```

The `target_kind` param is a cheap enum (0, 1, 2, 3). The driver
reads it back via `fsm.ghost_target_kind(i)` and uses it to pick
which targeting rule to apply:

```gdscript
func _chase_target(ghost_index: int) -> Vector2:
    var kind: int = fsm.ghost_target_kind(ghost_index)
    match kind:
        0:  return pacman_pos                            # Blinky: direct
        1:  return pacman_pos + pacman_dir * 80.0        # Pinky: ahead
        2:  return _flank(...)                           # Inky: flank
        3:  return _shy_target(...)                      # Clyde: shy
```

This is the **brain/body split doing real work**. The Frame system
knows which kind of ghost this is (a constant), and what mode it's
currently in (a state). The driver knows how to compute a target
position given those two pieces of information, and how to render
the ghost. Neither system needs to know what the other is doing.

### Why parameterization matters here

Without parameterization, you'd have four Frame systems — `Blinky`,
`Pinky`, `Inky`, `Clyde` — each a near-copy of the others. Adding
a "power ghost" mode (say, doubling everyone's speed after level
5) would mean editing four files. A bug fix to the frighten
transition would need to be applied four times.

With parameterization, the state machine is written once. The
differences are data. This maps perfectly to how Namco actually
designed the ghosts in 1980 — same ROM routine for all four, just
different targeting tables.

## Pacing: Why It Feels Right

Classic Pac-Man's scatter/chase alternation is the specific thing
that makes ghost behavior *feel* intentional rather than random.
Ghosts hunt aggressively for 20 seconds, then scatter to their
corners for 5–7 seconds, then hunt again. This gives the player
rhythm — windows when you can regroup and windows when you're being
hounded. Watch your game for a minute and you'll feel it.

In our Frame source:

```frame
actions:
    _scatter_duration() {
        if self.phase_index == 0: return 7.0
        if self.phase_index == 1: return 5.0
        return 5.0
    }
    _chase_duration() {
        if self.phase_index >= 3: return 9999.0
        return 20.0
    }
```

These numbers are taken from the original arcade. After three
chase cycles, Pac-Man locks into permanent chase — a difficulty
ramp that accepts the player no longer deserves scatter breaks.
That's expressed by the `>= 3: return 9999.0` line.

In the imperative world, this pacing is usually a timer class
with an enum and a switch that everyone has to remember to update
when changing states. Here it's two actions and a counter.

## The Stuff This Chapter Doesn't Teach

Worth being explicit about what's missing:

- **No maze.** Real Pac-Man ghosts pathfind on a tile grid. Our
  ghosts steer directly toward their target in open space. The
  state machine is the same; the geometry is different.
- **No Pac-Man lives or deaths.** The ghost catching Pac-Man
  should trigger his own explosion/respawn state machine. We
  don't ship that. `ghost_caught(index)` in the Frame source is a
  pass-through — it's wired up but the driver doesn't act on
  dangerous-ghost collisions.
- **No pellets (dots), just power pellets.** Adding 244 pellets
  across a maze is busywork; we'd need the maze first.

Each of these is a perfectly reasonable exercise. They'd also
each make the chapter twice as long without teaching anything
new about Frame.

## Exercises

**1. Add Pac-Man as a Frame system.** Four states: `$Alive →
$Dying → $Respawning → $Dead`. When a dangerous ghost collides
with Pac-Man (the case where `ghost_is_dangerous(i)` is true),
GhostGame calls `pacman.die()`. Notice: once you have a Pac-Man
system, his state affects which events the game accepts — no
input during `$Dying`, etc. This is chapter 3's Player FSM
pattern, adapted.

**2. Add a fifth ghost.** Give it a new target_kind value. One
line changed in the Frame source (new case in `_chase_target`
logic if you do targeting there — but actually targeting lives
in the driver, so no Frame change at all). Zero lines changed
in the state machine. This is the parameterization payoff made
visible.

**3. Replace the double-stack dance with a simpler design.**
Instead of each ghost having its own state stack, have GhostGame
remember what each ghost was doing when the frighten started,
and tell each ghost explicitly which mode to return to. Compare
the two designs — which is more code? Which is easier to reason
about? (My vote: the stack version is more *elegant* but the
explicit version is easier to *debug*. HSM + state stacks pay
more dividends in UI and workflow code than they do here.)

**4. Cornering.** In real Pac-Man, ghosts can't reverse direction
except at specific transition points. Implement this as a state
variable `$.can_reverse: bool = false` on each `$OutOfPen` child
state, flipped true by a `phase_changed_*` event and consumed by
the driver's steering logic. This exercise illustrates that
**state variables are still useful inside an HSM**.

**5. Elroy mode.** In real Pac-Man, when the pellet count drops
below certain thresholds, Blinky ("red ghost") accelerates and
switches personality — he becomes "Cruise Elroy". Add an
`$Elroy` state that's a third child of `$OutOfPen` alongside
`$Chase` and `$Scatter`. Think about what event triggers the
transition and where that event comes from.

## What's Next

Chapter 6 is **a platformer** — and after five chapters of
mostly-flat state machines, we'll see HSM used as a *matrix*.
The player character has movement modes (idle / walking / running
/ jumping / falling / landing) and power-up modes (small / big /
fiery), and these combine. A running-fiery character is
different from a jumping-small character. Without HSM, this
multiplies into 15+ states. With HSM, it's two orthogonal
hierarchies that Frame handles cleanly.
