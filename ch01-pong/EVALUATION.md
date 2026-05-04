# Pong: an honest evaluation

**Question:** Does Frame help build Pong, or is it overkill for
something this small?

**TL;DR:** Frame is **a clean win for Pong** — even though Pong is
small, the lifecycle is genuinely modal (attract → serving → in
play → point scored → game over) and the Frame source reads like
a state diagram. Plain GDScript would give you a `match game_state`
in `_physics_process` plus an enum, which is fine but worse to
read aloud and worse to extend. The single Pong system, 5 states,
~160 lines of Frame source is the smallest interesting Frame
example in the book.

---

## What was built

- `Pong` — single-system FSM with 5 states.
- 26-check smoke suite covering full lifecycle, restart, both
  winners.

**Frame source:** ~160 lines including comments
**Generated GDScript:** ~600 lines
**Driver:** ~390 lines (court, paddles, ball physics, AI, render)

---

## Per-system Frame value scoring

(Five-point scale: 5 = transformative; 3 = wash; 1 = pure
ceremony.)

| System | Score | Why |
|---|---|---|
| `Pong` | **4** | Five distinct states with clear transitions. The serve-toward-loser rule lives in `$PointScored.$>()` rather than scattered through a flag-on-the-base-machine. The serving_to direction is computed once at point-scored and read by the driver to render the ball position on the right paddle. Plain GDScript would do this in a `match` ladder; that works but doesn't read as cleanly. |

---

## What Frame demonstrably did well

### 1. Enter handlers compute derived state at the right moment

`$PointScored.$>()` decides serving direction and whether to
transition to game-over. The driver doesn't need to think about
when to recompute; the FSM does it on entry, exactly once.

### 2. The state name *is* the documentation

A reader who sees `$Serving` knows the ball is parked, the player
hasn't pressed launch yet, and physics is paused. Plain GDScript
with `game_state == GAME_STATE_SERVING` (as a constant) does the
same job in twice the space.

---

## What Frame demonstrably *didn't* help with

### 1. Ball physics

Velocity, position, paddle-collision, wall-bounce all live in the
driver. Frame doesn't pretend to model continuous physics, and
that's correct — physics is the body, FSM is the brain.

### 2. The AI paddle

A single `lerp` toward the ball Y position with a configurable
reaction speed. No FSM needed.

---

## Comparison: hypothetical Pong in plain GDScript

A plain GDScript Pong would have:

- An `enum GameState { ATTRACT, SERVING, IN_PLAY, ... }`.
- A `var state: GameState` and a `_physics_process` `match` ladder.
- The serve-direction logic as a method or inline.

Roughly the same total LOC. The Frame version reads better aloud
("when in $InPlay and ball_out_left fires, increment right's
score, last scorer was right, transition to $PointScored") but
the GDScript version is a few minutes of pattern recognition for
anyone who's seen `match` before.

**Honest call:** Frame wins on legibility, breaks even on size,
loses nothing. Pong is the right place to introduce the pattern
because the win is small and the cost is small — easy to grok
both.

---

## When to reach for Frame for a Pong-class game

**Use Frame when:**
- The game has 3+ distinct lifecycle modes that change behavior.
- You want to read the source and immediately see "what happens
  when X event fires in Y state."
- You're going to write more state machines later in the same
  codebase (Pong is chapter 1; the patterns recur).

**Don't reach for Frame when:**
- The game is one mode (a sandbox, a continuous simulation).
- You only need a single boolean flag.

For Pong: yes.
