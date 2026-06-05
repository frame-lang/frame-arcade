# Chapter 4 — Asteroids

Four states deep into the book, and Space Invaders showed us HSM. This
chapter introduces two features that complete the usual Frame
toolkit: **the state stack** and **parameterized systems**.

The state stack is easiest to motivate through a game mechanic that
doesn't exist in Pong, Breakout, or Invaders — **hyperspace**. In
Asteroids, the player can hit a button to briefly vanish and
reappear elsewhere, then return to whatever they were doing. That's
not a state *transition* in the usual sense. It's more like a
**function call**: interrupt what you're doing, do this other thing,
then come back. Frame's state stack gives you that directly.

Parameterized systems come in through **difficulty**. The same game
system should be able to spawn at easy, normal, or hard — with
different starting asteroid counts, different point multipliers,
different wave progressions. Frame's system parameters thread those
values through to the domain at construction time.

## What This Chapter Teaches

- **`push$` and `-> pop$`** — the state stack as a subroutine
  mechanism
- **Parameterized systems** — `@@system Name(param: type)` header
  syntax
- Reinforcement of HSM from chapter 3 (`$InGame` parent pattern
  repeats)
- Reinforcement of composition from chapter 2 (Ship and
  AsteroidField owned by Asteroids)

Still saving for later chapters:

- Deep HSM (multi-level parent chains) — chapter 5 (Pac-Man)
- The `@@persist` annotation for save states — ch 6 or later

## Running It

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

**Controls:**

| Key | Action |
|-----|--------|
| ← / → (or A / D) | Rotate ship |
| ↑ (or W) | Thrust |
| Space | Fire |
| H | Hyperspace |
| P | Pause / resume |
| Any key | Start game from attract mode |
| R | Restart after game over |

**Difficulty** is set in the inspector on `main.gd` via the `difficulty`
`@export` (1=easy, 2=normal, 3=hard). The difficulty value is passed
to the Frame system's constructor — see `_ready()` in the driver and
the Asteroids system header.

## The Three Systems

```
┌──────────────────────────────────────────┐
│  Asteroids(difficulty: int = 2)          │  HSM + parameterized
│  $Attract                                │
│  $InGame (HSM parent)                    │
│    ├── $Playing                          │
│    ├── $ShipDying                        │
│    └── $WaveClear                        │
│  $Paused                                 │
│  $GameOver                               │
│                                          │
│  domain:                                 │
│    difficulty = difficulty  ← from param │
│    ship  = @@Ship()           ─────────┐ │
│    field = @@AsteroidField()  ─────────┼─┤
└──────────────────────────────────────────┘  │
                                               │
            ┌──────────────────────────────────┘
            │
            ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│        Ship              │  │     AsteroidField        │
│  $Alive                  │  │  $Active                 │
│  $InHyperspace  ← push$  │  │                          │
│  $Exploding              │  │  domain:                 │
│  $Respawning             │  │    asteroids: Array = [] │
│  $Dead                   │  │                          │
└──────────────────────────┘  └──────────────────────────┘
```

The structure should look familiar — three systems, HSM on the top
level, composition through domain variables. The new bits are the
`$InHyperspace` subroutine state in Ship, and the `(difficulty: int)`
parameter on Asteroids.

## The State Stack: Hyperspace as a Subroutine

Open [`frame/asteroids.fgd`](./frame/asteroids.fgd) and find `$Alive`
in the Ship system:

```frame
$Alive {
    hit() {
        -> $Exploding
    }

    hyperspace() {
        push$
        -> $InHyperspace
    }
    ...
}
```

Then find `$InHyperspace`:

```frame
$InHyperspace {
    $.timer: float = 0.0
    $.duration: float = 0.4

    tick(dt: float) {
        $.timer = $.timer + dt
        if $.timer >= $.duration:
            -> pop$
    }
    ...
}
```

This is the state stack at its cleanest.

### What `push$` does

`push$` saves the **entire current compartment** onto a stack. A
compartment is the runtime representation of a state — not just its
identity, but all its state variables with their current values.
After `push$`, the current state is paused *as it was*.

Then `-> $InHyperspace` transitions normally. The state variable
`$.timer` in the new state initializes fresh (because entering a
state always re-runs its state variable initializers).

### What `-> pop$` does

`-> pop$` is not a normal transition. It **restores the pushed
compartment** — bringing back the state you were in, along with
every state variable it had at the moment of the push. If `$Alive`
had state variables they'd be waiting exactly where they were left.
(Our `$Alive` doesn't have any, but the mechanism is the same.)

Critically: the enter handler (`$>`) of the popped state **does
not** fire. You're not entering the state for the first time;
you're returning to where you were. If `$Alive` had an enter handler
that printed "welcome back," it would *not* run on pop. This is
usually what you want.

### Why not just use a normal transition?

You *could* express hyperspace with two normal transitions:
`$Alive → $InHyperspace → $Alive`. It would even look almost the
same. The difference is what happens to state variables.

Suppose `$Alive` had a state variable `$.shots_fired_this_life: int`
that counted shots since the last respawn. With normal transitions,
going `$Alive → $InHyperspace → $Alive` would reset `$.shots_fired`
to zero, because entering a state always reinitializes its state
variables. With `push$` / `-> pop$`, the count survives — it's the
same compartment being restored.

Hyperspace isn't *entering $Alive again*; it's **returning to $Alive
from a detour**. The state stack expresses that semantically.

More generally, the state stack is Frame's answer to **subroutines**.
Anywhere your imperative code would say "save what we were doing,
do this thing, then restore" — modal dialogs interrupting a main
flow, context-sensitive help overlays, inspection modes in an editor
— you've got a state-stack pattern waiting to happen.

## Parameterized Systems: Difficulty as a Constructor Arg

Look at the top of the Asteroids system:

```frame
@@system Asteroids(difficulty: int = 2) : RefCounted {
    ...
    domain:
        difficulty: int = difficulty
        ...
}
```

Two things are new:

**The `(difficulty: int = 2)` in the header** declares a system
parameter. When you instantiate the system, you pass a value:

```gdscript
var game = AsteroidsFSM.new(3)    # hard
```

or

```gdscript
var game = AsteroidsFSM.new()     # uses default of 2
```

**The `difficulty: int = difficulty` in the domain** is not a
typo. The LHS is the domain field name; the RHS is the constructor
parameter value. Frame rewrites this to something like
`self.difficulty = difficulty` in the generated constructor.

The parameter is in scope only while the domain initializers run.
After construction, only `self.difficulty` exists — you don't need
to remember which was the param and which was the field.

### Where parameterization pays off

In the Asteroids actions section:

```frame
_asteroids_for_wave(wave: int) {
    var base: int = 2 + self.difficulty    # 3/4/5 for diff 1/2/3
    return base + wave - 1
}
```

And in `bullet_hit_asteroid`:

```frame
bullet_hit_asteroid(index: int) {
    if self.field.split(index):
        var sz: int = self._size_points(index)
        self.score = self.score + sz * self.difficulty
        ...
}
```

Difficulty changes starting asteroid count and score multiplier.
Both are read from a single domain field — a field whose initial
value was set by the constructor param. If you want to add a
difficulty-aware change later (longer hyperspace cooldown on easy,
faster asteroid speed on hard), you put it in one more place: a
read of `self.difficulty` in whatever code cares.

The driver's `_ready()` passes the export var to the FSM:

```gdscript
@export var difficulty: int = 2

func _ready() -> void:
    fsm = AsteroidsFSM.new(difficulty)
    ...
```

You set the difficulty in the Godot inspector. Running it sends that
value into the Frame system's constructor. The game parameters
update accordingly. **The configuration plumbing is one line.**

### When to use system parameters

System parameters are for values that:

1. Need to be known at construction time (you can't change
   difficulty mid-game without rebuilding the system)
2. Configure the system's behavior, not its state

If the value changes during the game's lifetime (like the current
score), it's a domain variable that you assign to — not a parameter.
If the value varies between instances of the same system type
(like difficulty across save files), it's a parameter.

Frame also supports **state parameters** (`$(foo: int)`) and **enter
parameters** (`$>(foo: int)`) for passing values into specific
states. We don't need those here but they're documented in the Frame
language reference if you want to peek ahead.

## An Honest Quirk of the Driver

The driver has one small wart worth pointing out, because it
exposes a tension the chapter doesn't fully resolve:

```gdscript
var _last_ship_state: String = "Alive"

func _update_ship(delta: float) -> void:
    ...
    var current_state: String = fsm.ship.get_state()
    if _last_ship_state == "InHyperspace" and current_state == "Alive":
        ship_pos = Vector2(randf() * court_size.x, randf() * court_size.y)
        ship_vel = Vector2.ZERO
    _last_ship_state = current_state
```

When the ship finishes hyperspace, it should teleport to a random
spot. The Frame system handles the *mode* transition (`$InHyperspace`
→ `$Alive` via the timer in `$InHyperspace.tick`), but the *effect* —
setting a new position — lives in the driver. The driver detects
"just left hyperspace" by watching `get_state()` flip from
`"InHyperspace"` to `"Alive"`. Note that `get_state()` returns the
Frame state name verbatim (PascalCase, matches the FSM-diagram
labels) — defined once at the system level via `@@:system.state`,
not duplicated per state.

That's a little clumsy. A cleaner approach would be to use **exit
handlers** on `$InHyperspace`. When `-> pop$` fires, the exit
handler runs before the compartment is restored. That handler could
set a domain variable flag like `just_left_hyperspace = true` that
the driver reads and consumes.

Even cleaner: emit a callback to the driver. But Frame systems are
supposed to be driver-agnostic, so that pushes us toward dependency
injection patterns that feel heavy for a chapter on state stacks.

I'm leaving the clumsy version in because it demonstrates a real
truth: **the brain/body split is a design ideal, but the boundary
sometimes needs to be redrawn in practice.** If a mode transition
needs to cause a physical effect in the world, someone has to carry
that signal across the boundary. That's the driver's job.

(Exercise 3 below is "fix this properly." Do the exercise if you
want the full taste.)

## Why Individual Asteroids Aren't Frame Systems

This chapter could easily have been structured with each asteroid as
a Frame system — `@@system Asteroid(size: int)` — and that would
have given us *two* parameterized systems to show off. I didn't do
that. Here's why.

An asteroid has basically no state. It exists or it doesn't. It
moves by physics. When shot, it spawns children and dies. That's
not a state machine; it's data.

If we made each asteroid a Frame system, we'd pay the per-system
overhead (a class instance with a compartment, a state stack, a
kernel, a router, a dispatch function) for every one of the up to
~30 asteroids on screen, to store one bit and a position/velocity
pair. And for what? The system would have one state, and its
"interface" would be a setter and a getter. That's a class with too
much ceremony.

Instead, `AsteroidField` owns the whole collection as data. It has
one state (`$Active`) because it has no modes — it's just a bucket
of asteroids with operations on it. If later we wanted a "bonus
wave" mode where asteroids sparkle and spawn more children, that'd
be a new state on `AsteroidField` — the field has modes, even
though individual asteroids don't.

The lesson this keeps pressing on is: **Frame systems pay off when
something has modal behavior.** When it doesn't, they're just
clunky classes.

## Exercises

**1. Add hyperspace risk.** Classic Asteroids hyperspace had a small
chance of re-materializing inside an asteroid. Implement this: on
pop from `$InHyperspace`, 10% chance of `-> $Exploding` instead of
back to `$Alive`. Hint: you'll want an exit handler on
`$InHyperspace` that rolls a random number and conditionally
transitions. (Exit handlers run *before* the pop restores state.)

**2. Cooldown on hyperspace.** Prevent the player from hitting H
repeatedly. Add a `hyperspace_cooldown: float` domain variable and
a tick-based counter. Only allow the `hyperspace()` event to
actually push+transition when the cooldown is zero.

**3. Fix the hyperspace-exit teleport cleanly.** Use an exit
handler on `$InHyperspace` to set a domain flag on the Ship
(`just_teleported: bool`). The driver reads and clears the flag.
Compare how this feels against the `_last_ship_state` approach —
which do you prefer, and why?

**4. Add a UFO.** Like the exercise in chapter 3, but here the UFO
actually shoots at you. It's a new Frame system with states
`$Dormant → $Traversing → $Shooting → $Destroyed`. Owned by
Asteroids.

**5. Multiple difficulty tracks.** The current `difficulty` param
only affects starting asteroid count and score multiplier. Extend
it to also govern: asteroid speed, hyperspace cooldown, bullet
cooldown, fleet acceleration rate. You'll want to turn
`difficulty: int` into several `@export` vars in the driver and
pass each into the system. Consider: should the Frame system take
all of these as separate params, or take a single `difficulty
profile` structure? (The second is cleaner but Frame has no
first-class structure type — you'd use a Dictionary and document
its keys.)

## What's Next

Chapter 5 is **Pac-Man ghost AI**, which is where HSM *earns its
keep* in a way you've only seen hinted at so far. Each ghost has
four modes: chase the player, scatter to a home corner, flee
(frightened by power pellets), and return to the pen after being
eaten. The mode-switching is governed by game-wide events
(power pellet eaten, ghost returned to pen). With HSM, the code is
remarkably clean — maybe a hundred lines. Without HSM, it's the
messiest thing in classic game AI.

We'll also stop pretending that each character in a game needs its
own top-level `@@system` declaration. Four ghosts with the same
behavior but different targeting rules is the perfect case for
parameterized systems used to instantiate *multiple* instances of
the same type.
