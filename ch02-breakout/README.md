# Chapter 2 — Breakout

Pong was one state machine. Breakout is three, and that's the whole
point of this chapter. Real games have multiple things happening at
once — the ball has its own life cycle, the brick field has its own
state, and the game overall has modes that don't quite belong to
either. Trying to squeeze all of that into a single state machine
produces exactly the kind of tangle state machines are supposed to
prevent.

Frame's answer is **composition**: small, focused systems that hold
each other as fields and talk to each other through their interfaces.
By the end of this chapter you'll have a complete Breakout driven by
a `Breakout` system that owns a `Ball` and a `BrickField`, and you'll
have seen the pattern that scales Frame up to real game architectures.

## What This Chapter Teaches

- **Multi-system composition** — one system holding others as domain
  variables
- **Orchestration** — a parent system routing events to its children
- **State variables** (`$.foo`) for the first time — the ball's velocity
  lives on its `$InFlight` state, not as a domain variable
- When *not* to make something a Frame system (the paddle)

Concepts still deliberately *not* used here:

- Hierarchical state machines (chapter 3 will use them in earnest)
- The state stack / `push$` / `pop$` (chapter 4)
- Parameterized systems (chapter 3)

## Running It

```bash
./build.sh
godot --path godot/ scenes/main.tscn
```

Or open `godot/` as a Godot 4 project and hit the Play button.

**Controls:**

| Key | Action |
|-----|--------|
| ← / → (or A / D) | Move paddle |
| Space | Launch ball |
| Any key | Start game from attract mode |
| R | Restart after game over |

## The Three Systems

Here's the architecture at a glance:

```
┌──────────────────────────────────────┐
│            Breakout                  │   owns a ball and a brick field
│  states: Attract, Playing,           │   in its domain
│          LevelClear, GameOver        │
│                                      │
│  domain:                             │
│    ball    = @@Ball()       ─────────┼──┐
│    bricks  = @@BrickField() ─────────┼──┤
└──────────────────────────────────────┘  │
                                          │
            ┌─────────────────────────────┘
            │
            ▼
┌─────────────────────────┐  ┌─────────────────────────┐
│        Ball             │  │     BrickField          │
│  states:                │  │  states:                │
│    AttachedToPaddle     │  │    Active               │
│    InFlight             │  │                         │
│    Lost                 │  │  domain:                │
│                         │  │    bricks: [bool, ...]  │
└─────────────────────────┘  └─────────────────────────┘
```

The Godot driver (`main.gd`) talks *only* to the top-level Breakout
system. Breakout internally delegates to Ball and BrickField. The
driver has no idea those sub-systems exist.

### Why three systems?

You could do Breakout as one giant state machine. It would look
something like:

```
$Playing_BallAttached → $Playing_BallInFlight →
    (bricks 40) → (bricks 39) → ... → (bricks 0) → $LevelClear
```

That's horrible. The ball states get crossed with the brick count,
and adding any new ball state (e.g. `$Slowed` for a power-up) means
multiplying the whole state space. This is the **state explosion**
problem — two independent state variables combined into one
combinatorial mess.

Composition solves it. Ball has *its* states; BrickField has *its*
state; Breakout has game-flow states. Each is small and
comprehensible. They compose by reference: Breakout holds a Ball,
asks it questions, tells it what to do.

### Why not a Paddle system?

I deliberately didn't make the paddle a Frame system. Why?

The paddle has no modes. It's stateless: input goes in, position
comes out. Making it a state machine would be cargo-culting — a
single state called `$Moving` with no transitions isn't a state
machine; it's a class with extra ceremony. **Use Frame where state
matters. Keep stateless things as plain code.**

This is worth internalizing. Frame's value is in expressing discrete
modal logic. When your problem isn't modal, don't use a state
machine for it. The Godot paddle (lines ~100 of `main.gd`) is six
lines of clamp-to-bounds input handling — that's the right shape for
it.

## The Ball System, Walked Through

Open [`frame/breakout.fgd`](./frame/breakout.fgd) and find the Ball
system (around line 25).

```frame
@@system Ball : RefCounted {

    interface:
        launch(vx: float, vy: float)
        lose()
        attach()
        bounce_x()
        bounce_y()
        set_velocity(vx: float, vy: float)
        ...
```

The interface reads like a list of things that can happen *to* a
ball. Launch it, lose it, attach it, bounce it. The Godot driver
tells the ball about collisions; the ball's state machine decides
what that means.

### State variables: the first appearance

Inside `$InFlight`:

```frame
$InFlight {
    $.vx: float = 0.0
    $.vy: float = 0.0

    $>(vx: float, vy: float) {
        $.vx = vx
        $.vy = vy
    }
    ...
}
```

Notice the `$.` prefix. These are **state variables** — variables
that exist only while the system is in this particular state. When
the system transitions away from `$InFlight`, the velocity values
are freed. When it transitions back in, they're re-initialized from
the enter handler.

Compare this to Pong, where every number was a domain variable
(`self.score_left`, `self.winning_score`). Those are *persistent*
across state changes. The ball's velocity *isn't* — it only makes
sense while the ball is flying. Putting it on the state expresses
that relationship directly.

In imperative code, you'd manage this manually:

```gdscript
if state == "in_flight":
    # ball velocity is valid here
else:
    # hope nobody reads ball_vx here, it's stale
```

Frame gives you automatic lifecycle management for values tied to a
state. State variables are one of the features that shows up
repeatedly in real-world machines — any time a piece of data is
*only meaningful in a particular mode*, put it on that state.

### The transition that carries data

Look at how the ball gets launched:

```frame
# In $AttachedToPaddle:
launch(vx: float, vy: float) {
    -> (vx, vy) $InFlight
}

# In $InFlight:
$>(vx: float, vy: float) {
    $.vx = vx
    $.vy = vy
}
```

The `(vx, vy)` in `-> (vx, vy) $InFlight` is an **enter argument** —
values passed to the target state's `$>` enter handler. The enter
handler receives them positionally and stashes them in state
variables.

This is how you thread data through a state transition without going
through a domain variable. It's cleaner than setting a domain var
before transitioning, because it makes the data flow explicit: you
can *see* that the launch event carries velocity information into
the new state.

## The BrickField System, Walked Through

BrickField is deliberately simple — one state, four operations:

```frame
@@system BrickField : RefCounted {
    interface:
        reset(count: int)
        break_brick(index: int): bool
        is_broken(index: int): bool
        remaining(): int
        is_cleared(): bool

    machine:
        $Active {
            reset(count: int) { ... }
            break_brick(index: int): bool { ... }
            ...
        }

    domain:
        bricks: Array = []
        remaining_count: int = 0
}
```

Why make it a system at all, if it's only got one state?

Because **systems aren't just about modes — they're about
encapsulation**. BrickField owns a piece of game state (which bricks
are still present) and exposes a clean interface for querying and
mutating it. The rest of the game doesn't need to know it's a
`bool[]`; tomorrow it could be a 2D grid, or bricks with hit points,
or a procedural layout. The interface hides the representation.

This is just ordinary object-oriented design. Frame systems compose
cleanly with it because a Frame system *is* a class. The state
machine part might be trivial (one state), but the class identity
and interface contract still pay off.

You'll see more interesting BrickFields in later chapters — a
Breakout with indestructible bricks, multi-hit bricks, power-up
bricks, would add states like `$Active → $CascadingBonus →
$Active`. Starting with the simple version now means you have
somewhere to grow.

## The Breakout System, Walked Through

Now for the orchestrator. The `Breakout` system owns a `Ball` and a
`BrickField` in its domain:

```frame
domain:
    ball = @@Ball()
    bricks = @@BrickField()
```

`@@Ball()` is Frame's system-instantiation syntax. After
transpilation this becomes `Ball.new()` in GDScript. The ball is
constructed once when the Breakout system itself is constructed, and
it's owned for the whole lifetime of the game.

The interesting handlers are in `$Playing`:

```frame
$Playing {
    brick_hit(index: int) {
        if self.bricks.break_brick(index):
            self.score = self.score + self.points_per_brick
            self.ball.bounce_y()
            if self.bricks.is_cleared():
                -> $LevelClear
    }
    ...
}
```

When the driver reports a brick collision, Breakout:

1. Asks `bricks` to break the brick (returns true if it was actually
   there and got broken)
2. If so, adds score and tells `ball` to bounce
3. Asks `bricks` whether the level is now cleared
4. If cleared, transitions to `$LevelClear`

**This is what orchestration looks like.** The parent system makes
composite decisions — "if brick broke, then score, bounce, and maybe
advance" — by coordinating method calls on its children. The
children don't know about each other; they don't need to.

### The inter-system call pattern

Notice: nowhere does `Ball` know about `BrickField`, and nowhere does
`BrickField` know about `Ball`. They're completely independent. All
coordination happens in `Breakout`. That's the key discipline of
multi-system architecture:

> Children don't call each other. Only the parent calls children.

If you find yourself wanting to give the Ball a reference to the
BrickField, stop — the coordination probably belongs one level up,
in whatever parent holds both. Keeping children uncoupled is what
makes them individually testable and replaceable.

## Building and Running

```bash
./build.sh
```

The build script runs `framec` over `frame/breakout.fgd` and produces
`godot/scripts/breakout.gd`. Open the generated file and scroll
through it — you'll see three GDScript classes: `Ball`, `BrickField`,
and `Breakout`. The top-level class is `Breakout`, with the others
defined as auxiliary classes in the same file. All three have
`extends RefCounted` at the top, so they can be instantiated with
`.new()` from GDScript.

## The Godot Side

`main.gd` is bigger than Pong's, but the shape is identical: input
goes into the FSM, physics is gated by the FSM, queries come out.
The additions are:

- **Brick rendering** — `_draw()` walks all 40 brick indices, asks
  the FSM whether each is broken, and draws the ones that aren't
- **Brick collision** — `_check_brick_collision()` walks unbroken
  bricks, checks rect overlap with the ball, and fires `brick_hit(i)`
  on the FSM when it finds one
- **Ball parking** — when the ball is attached or lost, the driver
  keeps it pinned to the paddle (`_park_ball_on_paddle`)

Everything about *what* the game is doing lives in the Frame
systems. Everything about *how it looks and feels* lives in the
Godot driver. If you want to change the game to Arkanoid-style with
9×11 bricks and indestructible blocks, you edit the FSM. If you
want to change the visual style to pixel art with particle effects,
you edit `main.gd`. The two evolve mostly independently — that's
the payoff.

## Exercises

**1. Make bricks take two hits.** Modify `BrickField` to track hit
counts instead of booleans. The first hit should change the brick's
color but not remove it; the second hit breaks it. You'll need a
new interface method like `get_hits_remaining(index): int` and to
update `main.gd` to color the brick based on that.

This is a satisfying first exercise because the changes are
localized: BrickField's internals change, Breakout's logic is
unaffected (because the interface hides the change), and `main.gd`
just reads one new query.

**2. Add a power-up brick.** When a specific brick is broken, give
the player a wider paddle for 10 seconds. You'll want a new state in
`Breakout` (like `$Playing_WidePaddle`) or — better — a new Frame
system `PowerUpTimer` that the main game queries. Try both and see
which feels cleaner.

**3. Make the ball speed up every 5 bricks broken.** This one's
tricky: where does the speed tracking live? In the Ball? In
Breakout? In a new system? Your answer reveals what you think the
*responsibility* of each system is. (My preference: Breakout tells
the Ball to update its max speed, since Ball owns motion.)

**4. Two-ball mode.** After a level clear, start the next level with
two balls instead of one. This probably means the Ball system should
be parameterized — chapter 3 will formally introduce that pattern,
but you can preview it by instantiating `@@Ball()` twice in
Breakout's domain.

## What's Next

Chapter 3 is **Space Invaders** — three cooperating systems again,
but with an added twist: the invader fleet's behavior is a state
machine of its own (marching left, marching right, dropping down,
accelerating as fewer remain), and we'll want **parameterized
systems** for spawning invader instances with different positions
and types.

We'll also start leaning on **hierarchical state machines** (HSM)
for the first time — the game-over handling becomes boilerplate
across multiple states, and HSM parents are the way to eliminate
that duplication.
