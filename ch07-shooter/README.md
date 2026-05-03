# Chapter 7 — Side-Scrolling Shooter

The capstone. Everything you've learned, composed at scale.

This chapter doesn't introduce new Frame features — by chapter 6
the toolkit was complete. What it does is show what happens when
you reach for all of it at once: parameterized systems instantiated
dozens of times, HSM used where it genuinely helps (the multi-phase
boss), composition for the orchestrator, state variables for
transient timing, and the brain/body split holding everything
together across ~500 lines of Frame and a similarly-sized Godot
driver.

A real R-Type or Gradius is a year of content work. This chapter is
a shooter *demo* — enough to show the architecture working,
deliberately small enough to read end-to-end in an afternoon. By
the end you'll have seen a multi-phase boss and waves of enemies,
each enemy a parameterized Frame system with its own state machine,
all coordinated through one `Shooter` orchestrator.

## What This Chapter Demonstrates

Nothing new in Frame. Instead:

- **Parameterized systems used at scale** — the `Enemy` system
  instantiated dozens of times per wave, each with different
  params
- **Multi-phase boss as HSM** — three phases, each a parent
  state with its own child attack pattern states. This is the
  deepest HSM in the book.
- **Orchestration with heterogeneous children** — the `Shooter`
  system owns a Player, a Boss, and an array of Enemies. Three
  kinds of sub-system, one parent coordinating all of them.
- **When individual entities *are* Frame systems** — chapter 4
  argued against making individual asteroids FSMs. Chapter 7
  argues *for* making individual enemies FSMs. The difference
  is modal behavior, and the chapter explains why.

## Running It

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

**Controls:**

| Key | Action |
|-----|--------|
| Arrow keys (or WASD) | Move ship |
| Space | Fire |
| Any key | Start from attract mode |
| R | Restart after game over or victory |

Play for about 20 seconds. Enemies in three colors fly in from the
right:
- **Red** move in straight lines (easy)
- **Orange** oscillate up and down (sine wave)
- **Blue** swoop (harder, more HP)

After ten waves, a **boss** shows up. Watch its HP bar at the top
of the screen, and watch how its attack pattern changes at the 66%
and 33% HP thresholds:

- **Phase 1** (100% → 66% HP, purple): single shot, slow cadence
- **Phase 2** (66% → 33% HP, magenta): three-way spread
- **Phase 3** (33% → 0% HP, red): rapid angled spray

Kill the boss and you win. Die three times and you lose.

## The Four Systems

```
┌─────────────────────────────────────────────┐
│                Shooter                       │
│  $Attract → $Playing → $BossFight            │
│              → $Victory / $GameOver          │
│                                              │
│  domain:                                     │
│    player  = @@Player()       ────────┐      │
│    boss    = @@Boss()         ────────┤      │
│    enemies: Array = []   ← @@Enemy    │      │
│             × many                    │      │
└─────────────────────────────────────────────┘
                                         │
              ┌──────────────────────────┤
              │                          │
              ▼                          ▼
   ┌──────────────────┐     ┌──────────────────┐
   │     Player       │     │      Boss        │   HSM!
   │  $Alive          │     │  $PhaseOne       │   3 phases,
   │  $Exploding      │     │    ├ $P1Idle     │   each with
   │  $Invulnerable   │     │    └ $P1Firing   │   child states
   │  $Dead           │     │  $PhaseTwo       │
   └──────────────────┘     │    ├ $P2Idle     │
                            │    └ $P2Spread   │
   ┌──────────────────┐     │  $PhaseThree     │
   │   Enemy(kind,    │     │    ├ $P3Idle     │
   │   hp, fire_rate, │     │    └ $P3Spray    │
   │   points)        │     │  $Dying          │
   │  $Spawning       │     │  $Gone           │
   │  $Active         │     └──────────────────┘
   │  $Dying          │
   │  $Gone           │
   └──────────────────┘
```

## The Boss: The Book's Deepest HSM

The Boss is the single most elaborate state machine in the book.
Open [`frame/shooter.fgd`](./frame/shooter.fgd) and scroll to the
Boss system (around line 125).

### The structure

Three **parent states** for the phases, each with two **child
states** for the attack pattern rhythm within that phase:

```
$PhaseOne     (parent)
  ├── $P1Idle    → $P1Firing on timer → back to $P1Idle
  └── $P1Firing

$PhaseTwo     (parent)
  ├── $P2Idle    → $P2Spread on timer → back to $P2Idle
  └── $P2Spread

$PhaseThree   (parent)
  ├── $P3Idle    → $P3Spray on timer → back to $P3Idle
  └── $P3Spray

$Dying        (terminal sequence)
$Gone         (marker for orchestrator cleanup)
```

### The inheritance payoff

Look at `$PhaseOne`:

```frame
$PhaseOne {
    hit(damage: int) {
        self.hp = self.hp - damage
        if self.hp <= self.hp_start * 0.66:
            -> $P2Idle
        elif self.hp <= 0:
            -> $Dying
    }
    get_phase(): int { @@:(1) }
    ...
}
```

The `hit()` handler lives on the *parent*. Both `$P1Idle` and
`$P1Firing` inherit it via `=> $^`. When a player bullet hits the
boss during Phase 1, the event reaches $P1Idle or $P1Firing —
neither of which handles it — and forwards up to $PhaseOne, which
does the HP decrement and potential phase transition.

**The phase transition is one handler in one place**, regardless
of which child state the boss was in when hit. Without HSM you'd
need identical `hit()` handlers in every attack-pattern state
across every phase — six copies of the same logic, and a bug in
one is a bug in only one.

### Phase transitions happen through children

Notice: `-> $P2Idle` from `$PhaseOne.hit()` transitions to a
*child of a different phase*. That's a transition that *crosses
a parent boundary*. Frame handles this cleanly: it exits the
current child, exits the current parent (Phase One), enters the
new parent (Phase Two via the natural ancestry chain), and
enters the new child (P2Idle).

Each phase's child states have their own timers and state
variables. `$P1Idle.$.timer` is distinct from `$P2Idle.$.timer`.
When you transition from `$P1Idle` to `$P2Idle`, the old state
variable is discarded and the new one is freshly initialized. No
cross-state stale values.

### Why separate child states per phase, rather than shared?

I could have had one `$Idle` and one `$Firing` that every phase
transitions between, and kept a domain variable for current
phase. Let me justify the more explicit structure:

- **Different phases have different timing.** $P1Idle is 1.8s;
  $P3Idle is 0.6s. Those are state variables on each state,
  set in the declaration — they can't be "one idle" without
  losing the per-phase difference.
- **Different phases have different attacks.** $P1Firing fires
  one bullet; $P2Spread fires three; $P3Spray fires at a rapid
  cadence. The fire logic is in the child state.

The phases genuinely have distinct behaviors beyond HP thresholds.
HSM expresses this faithfully — the "this is a firing state"
shape is shared (each has a timer and a fired-flag and a duration)
but the specifics differ.

## The Enemy System: Parameterized At Scale

Chapter 4 parameterized one system for difficulty. Chapter 5
parameterized Ghost for four instances with different targeting
rules. This chapter parameterizes Enemy for **many instances** —
waves of three enemies every 2 seconds, ten waves before the boss.

Each enemy is constructed with four parameters:

```gdscript
var EnemyClass = ShooterFSM.Enemy
var enemy = EnemyClass.new(kind, hp, rate, points)
fsm.add_enemy(enemy)
```

Same class, different configurations. The Frame system's state
machine is identical for all enemies — they all go through
`$Spawning → $Active → $Dying → $Gone`. The *behavior* during
each state depends on the params, and the driver reads those
params to decide how to move and render:

```gdscript
match kind:
    0:  # straight — constant leftward velocity
    1:  # sine — leftward with vertical oscillation
    _:  # swoop — leftward with bigger y swings
```

### Why enemies *are* Frame systems here (when asteroids weren't)

Back in chapter 4 I argued against making each asteroid a Frame
system. Asteroids had no modes — they existed or didn't. The
whole collection became `AsteroidField`.

Enemies are different. An enemy has:

- A spawn phase (invulnerable while entering)
- An active phase (moves, shoots on a timer)
- A dying phase (plays death animation)
- A cleanup phase (marker for removal)

That's four *modes*. Events depend on what mode we're in —
`hit()` in $Spawning does nothing; `hit()` in $Active does damage;
`hit()` in $Dying is ignored. The state variable `$.fire_timer`
accumulates only during $Active. This is genuinely modal
behavior, and putting it in a state machine makes the rules
structural.

**When in doubt, ask: does the object's response to events depend
on more than its data?** If yes, FSM. If no, data.

## The Orchestrator: Heterogeneous Children

`Shooter` owns three kinds of sub-systems:

```frame
domain:
    player = @@Player()
    boss = @@Boss()
    enemies: Array = []
```

Player is a single instance. Boss is a single instance. Enemies
is a variable-length array. Each tick, Shooter ticks all of them
and routes events:

```frame
$Playing {
    tick(dt: float) {
        self.player.tick(dt)
        self._tick_enemies(dt)
        self.wave_timer = self.wave_timer + dt
        if self.waves_spawned >= self.waves_before_boss:
            -> $BossFight
    }
    ...
}
```

Wave and boss transitions live on the parent (Shooter). The
children (Player, Enemy, Boss) don't know about each other or
about the wave count. Each does its own job.

This is **composition done right**. The parent knows about all
its children; children don't know about each other; the parent
decides when and how to invoke each child's interface. If you
want to add a new sub-system — say a `ShieldGenerator` that
Pac-Man-style power-up blocks — you add it to Shooter's domain
and its interface, and nothing else in the code needs to change.

## Looking Back: What You've Built

Seven chapters, seven games, roughly two thousand lines of Frame
and four thousand of GDScript. Features you've used:

| Feature | Introduced in | Used in |
|---------|--------------|---------|
| Basic states and transitions | Pong | Every chapter |
| Enter handlers (`$>`) | Pong | Every chapter |
| Exit handlers (`<$`) | Pac-Man | Pac-Man |
| Domain variables | Pong | Every chapter |
| Multi-system composition | Breakout | Every chapter since |
| State variables (`$.`) | Breakout | Breakout, Player FSMs, Platformer |
| HSM (parent states + `=> $^`) | Invaders | Invaders, Pac-Man, Platformer, Shooter |
| State stack (`push$` / `-> pop$`) | Asteroids | Asteroids, Pac-Man |
| Parameterized systems | Asteroids | Asteroids, Pac-Man, Platformer, Shooter |
| Actions (`actions:`) | Invaders | Invaders, Pac-Man, Shooter |
| `@@:return(expr)` form | Breakout | Throughout |
| Base class inheritance (`: RefCounted`) | Pong (after bug fix) | All |

And patterns that emerged:

- **Brain/body split**: Frame holds modes, Godot holds physics and
  rendering
- **Owner drives the children**: orchestrator calls `tick()` on each
  sub-system
- **Queries return values; events trigger state changes**
- **One-shot signals**: `wants_jump_impulse()` / `consume_jump_impulse()`
- **Children don't know about each other**; only the parent coordinates
- **Stateless things stay in the driver**; modal things become Frame
  systems
- **Orthogonal state dimensions** → two FSMs, not one big HSM
- **State variables** for per-state timers and flags; **domain
  variables** for cross-state persistent data

## Where To Go From Here

The book is complete, but Frame isn't done with games. A few
places to take this architecture next:

### 1. The colossal cave adventure you mentioned earlier

A text adventure is almost pure state machine — rooms are states,
objects have states, the whole game is a graph of modal responses
to commands. Frame handles this beautifully and the architecture
is totally different from arcade games. Worth a follow-up
project.

### 2. Harder-AI games

Now that you've seen HSM for game AI (chapter 5's ghosts), try:

- **Stealth game AI** — guards with modes like patrolling /
  investigating / alerted / searching / attacking. Classic HSM
  territory, and a good case study for the "Frame vs. Behavior
  Trees" conversation from earlier.
- **Turn-based strategy AI** — units with move/attack/defend
  phases, AI that decides actions in turn. Very different from
  real-time and the state stack starts earning its keep for
  "consider this action, simulate it, roll back."

### 3. Retargeting

Every Frame source file in this book is in `.gd` form targeting
`gdscript`. Every one of them would *also* compile to Python,
TypeScript, Rust, C, or any of Frame's ~17 backends. You could
take the Pac-Man ghost AI spec and drop it into a Bevy (Rust)
game or a Three.js (TypeScript) game, and the state machine
would work identically.

That's the deep promise of Frame that this book couldn't fully
demonstrate because we were constrained to Godot: **the
behavioral spec is portable.** The same ghost AI in Bevy with a
procedural maze would be the same Frame file, a different
driver.

### 4. Save/load

We didn't touch `@@persist` in this book. It's the Frame feature
that serializes the entire system state to disk in one call and
restores it — useful for games with long play sessions (RPGs,
strategy games, roguelikes). Chapter 44 in the cookbook walks
through the mechanics.

### 5. Multiplayer

Frame systems are plain classes. They serialize cleanly. They can
be sent over the wire. A multiplayer version of any of these
games would have the Frame system running on the server; clients
would receive state snapshots or event streams. The brain/body
split becomes a server/client split.

## Exercises

**1. Add a mid-boss.** Between wave 5 and wave 6, spawn a smaller
boss with two phases instead of three. Reuse the `Boss` system's
HSM pattern but parameterize on `max_hp` and `phase_count`.
(This exercise forces you to actually parameterize the boss
itself, which the shipped code does not — the boss is
hardcoded with 300 HP.)

**2. Power-ups.** Drop a power-up occasionally when killing an
enemy. Create a `PowerUp` Frame system with states `$Falling →
$Collected` and an interface method `apply_to(player)`. Different
kinds (spread shot, rapid fire, shield) are different
parameterized PowerUp instances.

**3. Dynamic difficulty.** The Shooter's `waves_before_boss` and
`wave_interval` are hard-coded domain variables. Make Shooter
take a `difficulty: int` param (like chapter 4) and scale those
values by difficulty. Compare how this feels when set to 1
(easy) vs. 3 (hard).

**4. The wave script problem.** Real shooters have *choreographed*
waves — "at t=15s, spawn a squadron of five blue enemies in a V
formation." Design a data-driven wave system. Is it a new Frame
system? A plain data structure with entries the driver reads? A
table the wave manager consults? Think about which approach
keeps the boundaries clean.

**5. Compare this architecture against your previous
implementation of any game.** If you've written a shooter or
platformer before (in any engine, any language), compare your
previous code to the Frame version. Is the state model more or
less explicit? How many bugs in your prior version were
"transition not handled correctly" bugs that would have been
structural in Frame?

## Where To From Here, Really

You've now written seven games' worth of state machine code. The
mental model — decompose by state, compose by system, draw
boundaries where modes change — should feel more natural than it
did back in chapter 1. The toolkit is small (transitions, enter
handlers, HSM, state stack, composition, parameters) but the
combinations cover an enormous design space.

The best thing you can do with it is use it. Take a game you want
to build, describe its states, draw the graph, write the Frame
first and the rendering second. You'll find problems that *used*
to require clever structure now require just accurate structure.
That's what the book was for.

Good luck with the next one.
