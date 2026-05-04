# Breakout: an honest evaluation

**Question:** Does Frame help when there are three FSMs that need
to coordinate, or does the orchestration get in the way?

**TL;DR:** Frame is **a 4/5 win for Breakout**. The three-system
composition (Ball + BrickField + Breakout-orchestrator) is the
first place in the book where the orchestrator pattern earns its
keep. The Ball's state-variable velocity (`$.vx, $.vy` on
`$InFlight`) is the cleanest small demonstration of "state variables
live for the duration of the state, no stale data" in the whole
arcade.

---

## What was built

- `Ball` — 3 states, with `$InFlight.$.vx, $.vy` state variables.
- `BrickField` — single-state container for brick array.
- `Breakout` — orchestrator with $Attract / $Playing / $LevelClear
  / $GameOver lifecycle.

**Frame source:** ~340 lines
**Generated GDScript:** ~1500 lines
**Driver:** ~600 lines (court, paddle, ball physics, brick render)
**Smoke tests:** 39 checks covering all three FSMs + cross-FSM.

---

## Per-system Frame value scoring

| System | Score | Why |
|---|---|---|
| `Ball` | **4** | State variables on `$InFlight` (vx, vy) are exactly the right shape — they don't exist when the ball is attached to the paddle, and they're freshly initialized on every launch. Plain GDScript would carry stale velocity in an instance variable across launches; the bug class is precluded. |
| `BrickField` | **2** | Single state, all the logic is in the brick array. The system gives you a clean interface (`break_brick(i): bool`, `is_cleared()`) but the FSM scaffolding is ceremony. |
| `Breakout` | **5** | Four-state orchestrator that routes events to the right sub-system: brick_hit → bricks.break_brick + ball.bounce_y; paddle_hit → ball.set_velocity; ball_fell_off → decrement lives. The orchestrator pattern is *introduced* here and goes on to power every multi-system chapter (Invaders, Asteroids, Pac-Man, Shooter, Stealth, CCA). |

---

## What Frame demonstrably did well

### 1. State variables forbid the stale-data bug

The ball's velocity is stored as `$.vx` and `$.vy` on
`$InFlight`. Each entry to `$InFlight` initializes them fresh.
You literally cannot accidentally read last serve's velocity in
this serve.

### 2. Cross-FSM event routing

`$Playing.brick_hit(index)` calls `bricks.break_brick(index)`,
checks the return value to decide whether to update score, calls
`ball.bounce_y()`, then checks `bricks.is_cleared()` and
transitions to `$LevelClear` if so. Every cross-cut is one line,
nothing implicit.

### 3. Composition under `@@[persist]` (latent)

This chapter doesn't yet use save/restore (the cabinet's
`asteroids.fgd` variant adds it for chapter 4), but the
composition shape Breakout introduces — `domain: ball =
@@Ball()` + `bricks = @@BrickField()` — is exactly what
`@@[persist]` auto-traverses later. Readers who get to chapter 4
or CCA see this pattern recur with persistence layered on.

---

## What Frame demonstrably *didn't* help with

### 1. BrickField as a "system"

`BrickField` is one state with five interface methods. It exists
to expose a clean interface around an Array, not because brick
state is genuinely modal. Plain GDScript with a `BrickField`
class and the same five methods would be ~30 lines instead of
~50. The Frame ceremony is real.

The chapter's stated reason for keeping it as a `@@system`
anyway is teaching: it shows that "system" can mean "encapsulated
piece of state," not "interesting FSM," and that the orchestrator
pattern doesn't require every participant to be an HSM.
Reasonable trade-off.

### 2. Ball physics

Velocity update and collision detection live in the driver. Frame
doesn't model continuous physics; the driver feeds discrete events
(bounce_x, bounce_y, paddle_hit) into the FSM. Correct division
of labor.

---

## Comparison: hypothetical Breakout in plain GDScript

- `Ball` as a class with a `state` enum and `match` in physics:
  ~60 lines, equivalent.
- `BrickField` as a wrapper class around an Array: ~40 lines,
  smaller than Frame.
- `Breakout` as an orchestrator with `match game_state`: ~80 lines,
  equivalent.

**Net:** Frame is roughly equivalent in LOC, slightly clearer
when reading the orchestrator's event-routing logic, and
preserves the state-variable-velocity bug-class-prevention that
plain GDScript can't easily replicate without a per-launch reset
ritual.

---

## When to reach for Frame for a Breakout-class game

**Use Frame when:**
- You have 2+ sub-systems whose states need to coordinate.
- One or more sub-systems has phase-specific data (state
  variables) that should not survive between phases.
- You're building toward save/restore, even if it's not in
  scope yet — Frame's composition shape is the foundation.

**Don't reach for Frame when:**
- Your "sub-system" is a wrapper around a single Array. Use a
  GDScript class.
- All the modal logic fits in one `match` block.

For Breakout: yes — chapter 2 introduces composition + state
variables + orchestration in the smallest example that needs all
three.
