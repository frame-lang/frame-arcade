# Chapter 3 — Space Invaders

Breakout was composition: two children, one parent, parent
orchestrates. Space Invaders is composition *plus* two new ideas:

- **Hierarchical state machines (HSM).** The top-level game has
  several states that all share common behavior (pause, queries).
  HSM lets us write that behavior once in a parent state and have
  the children inherit it.
- **Non-trivial sub-system FSMs.** Breakout's Ball had three states
  that were mostly about "attached vs flying vs gone." Space
  Invaders' Fleet has genuine modes — marching left, marching
  right, stepping down — and the famous *speedup as invaders die*
  mechanic falls out of one domain variable.

By the end of this chapter you'll have playable Space Invaders with
waves, a self-accelerating alien fleet, a pausable game, and an
HSM demonstration that shows why Frame's hierarchy feature matters.

## What This Chapter Teaches

- **HSM parent states** with `=> $Parent` and default forwarding
  via `=> $^`
- The pattern of a parent state that's never entered directly
- Non-trivial multi-system composition — three cooperating FSMs
- The *emergent-pacing-from-one-variable* technique, which
  distributes cleanly in Frame where it's a tangle in imperative code

Still not used (saving for chapter 4):

- The state stack (`push$` / `pop$`)
- Parameterized systems

## Running It

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

**Controls:**

| Key | Action |
|-----|--------|
| ← / → (or A / D) | Move ship |
| Space (or ↑) | Fire |
| P | Pause / resume |
| Any key | Start game from attract mode |
| R | Restart after game over |

## The Three Systems

```
┌─────────────────────────────────────┐
│          Invaders                   │  HSM: $Attract →
│  $Attract                           │       $Playing → $PlayerDying
│  $InGame (parent — never entered)   │           → $Playing
│    ├── $Playing                     │           → $WaveComplete
│    ├── $PlayerDying                 │       $Paused, $GameOver
│    └── $WaveComplete                │
│  $Paused                            │
│  $GameOver                          │
│                                     │
│  domain:                            │
│    player = @@Player()  ─────────┐  │
│    fleet  = @@Fleet()   ─────────┼──┤
└─────────────────────────────────────┘  │
                                          │
          ┌───────────────────────────────┘
          │
          ▼
┌─────────────────────┐   ┌─────────────────────┐
│     Player          │   │       Fleet         │
│  $Alive             │   │  $Marching          │
│  $Exploding         │   │  $Stepping          │
│  $Invulnerable      │   │  $Defeated          │
│  $Dead              │   │                     │
└─────────────────────┘   └─────────────────────┘
```

Three FSMs. The Godot driver talks only to Invaders; Invaders talks
to Player and Fleet.

Why these three and no others? By the same rule as Breakout: **use
Frame where state matters, plain code where it doesn't.** An
individual invader is not a state machine — it's a position and an
alive/dead bit. The Fleet owns that array. A bullet is not a state
machine — it's a position moving in one direction until it exits the
screen or hits something. The Godot driver owns bullets as a plain
array.

If you find yourself tempted to make every game object a Frame
system, stop and ask: does this object have *modes*? Does its
response to events depend on more than its data — does it depend on
*what state it's in*? If yes, Frame. If no, plain code.

## The Big New Idea: Hierarchical State Machines

Here's the motivation. In Pong and Breakout, every state had to
redefine every query:

```frame
$Attract {
    get_score(): int { @@:(self.score) }
    get_lives(): int { @@:(self.lives) }
    get_wave(): int  { @@:(self.wave) }
    ...
}
$Playing {
    get_score(): int { @@:(self.score) }    # same as $Attract
    get_lives(): int { @@:(self.lives) }    # same as $Attract
    get_wave(): int  { @@:(self.wave) }     # same as $Attract
    ...
}
$LevelClear {
    get_score(): int { @@:(self.score) }    # and again
    ...
}
```

The queries are the same in every state because the underlying data
is the same. Only when a state needs to return something
*different* (like `$GameOver.get_state(): String { @@:("game_over")
}`) does it differ. This is a classic DRY violation, and it gets
worse as you add states.

Space Invaders has *six* states (Attract, Playing, PlayerDying,
WaveComplete, Paused, GameOver). Writing the same three query
handlers six times each is eighteen copies of the same line. And
when you add a seventh state, you have to remember to add all the
queries to it or they'll silently break in that state.

### Parent states and inheritance

The fix: declare a parent state that owns the common handlers, and
make the active-gameplay states children of it. Open
[`frame/invaders.fgd`](./frame/invaders.fgd) and find `$InGame`:

```frame
$InGame {
    pause() {
        -> $Paused
    }
    get_state(): String { @@:("in_game") }
    get_score(): int    { @@:(self.score) }
    get_lives(): int    { @@:(self.player.get_lives()) }
    get_wave(): int     { @@:(self.wave) }
    is_paused(): bool   { @@:(false) }
}

$Playing => $InGame {
    tick(dt: float) { ... }
    player_killed_invader(index: int) { ... }
    get_state(): String { @@:("playing") }
    => $^
}

$PlayerDying => $InGame {
    tick(dt: float) { ... }
    get_state(): String { @@:("player_dying") }
    => $^
}

$WaveComplete => $InGame {
    tick(dt: float) { ... }
    get_state(): String { @@:("wave_complete") }
    => $^
}
```

The `=> $InGame` after the state name says "`$Playing` is a child
of `$InGame`." The `=> $^` at the end of each child says "forward
every unhandled event up to my parent."

Consequences:

- `pause()` is defined once, in `$InGame`. All three children get it
  by forwarding. Calling `pause()` from `$Playing` transitions to
  `$Paused` without any code in `$Playing` itself.
- `get_score`, `get_lives`, `get_wave`, `is_paused` are defined
  once, in `$InGame`. Children get them for free.
- `get_state()` is **overridden** in each child — they each return
  their own state name. This is how Frame's HSM resolution works:
  when a handler is defined in both child and parent, the child
  wins.

### One subtlety: `$InGame` is never entered directly

Look at the transitions in the file. Nothing ever says `-> $InGame`.
The parent state exists purely as a container for shared handlers.
It's a **pure abstract state** in the object-oriented sense — a
base class that defines common behavior but is never instantiated
on its own.

This is a common and useful HSM pattern. Don't let yourself get
hung up on "but what *is* $InGame?" It's a rhetorical grouping — a
place to put handlers that apply to a set of concrete states.

### Why explicit forwarding instead of automatic?

Some HSM systems (like UML statecharts) forward unhandled events to
the parent *automatically*. Frame does it *explicitly* — you have to
write `=> $^`. Why?

Because automatic forwarding is a footgun. You add a state, forget
it inherits `pause()` from a distant ancestor, and suddenly an event
you didn't expect triggers behavior you don't want. Explicit
forwarding makes the inheritance relationship visible at every
child. The `=> $^` at the bottom of `$Playing` says in code: "yes,
I am a member of the $InGame family; treat me like one."

If you want selective inheritance — say, `$Playing` should forward
`pause()` but handle `tick()` without forwarding — you just write
the explicit forward inside the specific handler:

```frame
$Playing => $InGame {
    tick(dt: float) {
        self.player.tick(dt)
        self.fleet.tick(dt)
        # No forward — we fully handle tick() here
    }
    pause() {
        log_pause()
        => $^     # Handle it locally AND forward to parent
    }
    # No trailing `=> $^` — unhandled events are ignored, not forwarded
}
```

Frame gives you precise control over what inherits what. It's more
verbose than automatic forwarding, but it's harder to trip over
later.

## The Fleet's Self-Accelerating March

This is the chapter's showcase mechanic — and one of the clearest
cases of "Frame expresses the right thing in the right place."

In 1978's Space Invaders, the fleet's march gets faster as more
aliens are killed. By the time one alien remains, it's whipping
across the screen. Historically this was partly a hardware
accident (fewer aliens = fewer sprites to update = faster frame
rate), but it became iconic and every re-implementation preserves
it deliberately.

### The imperative version

The typical imperative implementation looks something like:

```python
class Invader:
    def update(self, dt, world):
        move_interval = 0.6 - (55 - world.alive_count()) * 0.01
        self.time_since_last_move += dt
        if self.time_since_last_move >= move_interval:
            self.x += world.direction * STEP_SIZE
            self.time_since_last_move = 0
```

The pacing formula is distributed to every invader, even though it's
a property of the fleet. Every invader re-derives it from
`world.alive_count()`. When you want to change the formula — say,
make it a curve instead of linear — you edit every call site, or
you refactor to pull the formula out, at which point you're
reinventing a `Fleet` class anyway.

### The Frame version

In `Fleet`, the pace lives on the fleet (where it conceptually
belongs), it's recomputed whenever an invader dies, and the state
machine reads it each tick:

```frame
actions:
    _update_pace() {
        if self.total_invaders <= 0:
            return
        var live: int = self._count_alive()
        var frac: float = float(live) / float(self.total_invaders)
        self.step_interval = self.min_step_interval + (
            self.initial_step_interval - self.min_step_interval) * frac
    }
```

And in `_do_kill`:

```frame
_do_kill(index: int) {
    if index < 0 or index >= self.alive.size():
        return false
    if not self.alive[index]:
        return false
    self.alive[index] = false
    self._update_pace()    # ← one line. That's the whole mechanic.
    return true
}
```

The pacing lives in *one place*. Invaders don't know about pacing;
the fleet does. Invaders don't exist as individual systems at all —
they're just entries in `self.alive`, managed by the fleet. The
state machine reads `self.step_interval` in `$Marching` and triggers
a march step when the timer exceeds it.

**This is the shape Frame keeps nudging you toward.** State and the
logic that depends on state are colocated. Distributed derivations
become centralized properties.

## The Player's Invulnerability Window

A small but worth-noting detail. After the player dies and a life
is deducted, they respawn with 1.5 seconds of invulnerability — a
brief immunity so they don't immediately die again to an alien
bullet still in flight.

In the Player FSM, this is three states:

```
$Alive ──(hit)──▶ $Exploding ──(1.2s timer)──▶ $Invulnerable ──(1.5s)──▶ $Alive
                                                       └── if lives==0 ──▶ $Dead
```

The `can_be_hit()` query returns `true` only in `$Alive`. The
Godot driver checks this before registering a collision. The
entire "brief invulnerability" mechanic is just *a state the
player is in*. No flags, no countdown variables scattered
around — just a state with a timer state variable that, when it
expires, transitions back to $Alive.

This is what state-first thinking looks like in practice.
"Invulnerable" isn't a boolean on the player. It's a *phase of
their existence*.

## Running and Tweaking

Build and run:

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

Numbers worth experimenting with in `main.gd`:

- `alien_fire_chance_per_sec` — how aggressive the invaders are
- `fleet_horizontal_step` — how far the fleet moves per march step
- `player_shot_cooldown` — rate of fire (lower = faster)

And in `frame/invaders.fgd`:

- Player `$.duration: float = 1.5` — length of invuln window
- Fleet `min_step_interval: float = 0.06` — maximum fleet speed

The Frame-side tunables give you gameplay behavior. The Godot-side
tunables give you visual feel. That split stays clean because the
architecture maintains it — change one, the other doesn't need to
know.

## Exercises

**1. Add a bunker system.** Classic Invaders has four destructible
bunkers between the player and the fleet. Decide: is this a Frame
system or plain Godot? (My vote: plain Godot. The bunkers have no
modes; they're just textures that lose pixels on hit. But write out
*why* you'd not make it a Frame system — that muscle matters.)

**2. Add a UFO.** The mystery ship that crosses the top of the
screen periodically. It has genuine modes: `$Dormant →
$Traversing → $Destroyed`. Make it a new `@@system UFO` and have
Invaders own it. You'll find `$Dormant` needs a timer.

**3. Experiment with the HSM.** Try removing `=> $^` from
`$Playing` and watch what happens when you press P. Pause stops
working, because without the explicit forward, the `pause()` event
doesn't reach `$InGame`'s handler. Put it back.

Then try *adding* a `pause()` handler to `$Playing` directly — one
that logs "pausing from Playing" before forwarding. You'll use
in-handler `=> $^` to forward after the log. This is the selective
pattern the chapter mentioned.

**4. Refactor for point values per row.** In real Invaders, the
top rows of aliens are worth more. Add point values per row in
`Fleet`'s domain, and change `player_killed_invader` to read the
actual value. Notice: this change is entirely internal to Fleet
and Invaders. The Godot driver doesn't need to know.

## What's Next

Chapter 4 is **Asteroids** — the first chapter to use the state
stack (`push$` / `pop$`) for the hyperspace mechanic, and the first
to use **parameterized systems** for instantiating different
asteroid sizes from a single system definition. We'll also start
thinking about scale: Asteroids has many active entities on screen
at once, and the question of *what should be a Frame system vs.
just data* gets sharper.
