# Space Invaders: an honest evaluation

**Question:** Does the HSM pattern earn its complexity in
Invaders, or could a flat machine carry the load?

**TL;DR:** Frame is **a 4/5 win for Invaders**. The Invaders
top-level uses HSM with `$InGame` as parent of `$Playing /
$PlayerDying / $WaveComplete`, and the parent owns pause +
common queries. The pace-up-as-invaders-die mechanic is one
domain variable (`step_interval`) recomputed in `_update_pace()`,
which would have been distributed across update paths in plain
GDScript.

This chapter also surfaced **framec Issue #4** (transition inside
nested-if + outer fall-through `@@:(value)` drops return) — see
`FRAMEC_BUGS.md`. Resolved by spec (W705 warns at compile time);
fixed in source by placing `@@:return(value)` at each transition
site.

---

## What was built

- `Player` — 4-state lifecycle (alive / exploding / invulnerable
  / dead) with `$.timer` state variables on the timed states.
- `Fleet` — 3-state ($Marching / $Stepping / $Defeated) with
  pace-up logic and direction reversal at edges.
- `Invaders` — top-level HSM with `$InGame` parent for
  `$Playing`, `$PlayerDying`, `$WaveComplete`.

**Frame source:** ~540 lines
**Generated GDScript:** ~2000 lines
**Driver:** ~830 lines
**Smoke tests:** 35 checks covering all three FSMs + HSM
parent-state + pause/resume + wave clear.

---

## Per-system Frame value scoring

| System | Score | Why |
|---|---|---|
| `Player` | **4** | Timed states with `$.timer` + duration on `$Exploding` and `$Invulnerable`. Each entry resets the timer; tick() advances it; threshold transitions to next state. The "can_fire during invulnerable" override matters for game feel and is one line. |
| `Fleet` | **5** | Step-interval recompute on every kill is the iconic mechanic. The pace-up formula lives in `_update_pace()`, called once from `_do_kill()`. Plain GDScript would scatter this across the kill-handler and every place that reads `step_interval`. The deterministic "did the timer expire" via `consume_step()` separates physics (the driver's tick) from game-logic (the FSM's threshold check) cleanly. |
| `Invaders` | **5** | HSM parent `$InGame` owns the shared `pause()` handler and common queries. `$Playing`, `$PlayerDying`, `$WaveComplete` all `=> $^` to dispatch unhandled events upward. Adding a 4th gameplay sub-state is one new state with `=> $InGame` and the right local handlers — no parent surgery. The HSM payoff is real here. |

---

## What Frame demonstrably did well

### 1. HSM parent owns common behavior

`$InGame.pause()` + `$InGame` queries are written once. Children
override only what differs. When a 4th gameplay sub-state would
land (e.g., `$BossFight` for a boss-rush variant), it gets
pause-handling for free.

### 2. State-variable timers + tick

`$Exploding.$.timer + $.duration` is the smallest possible
"animate this for N seconds, then transition" idiom. `$.timer`
is freshly zero on entry; nothing carries over from a previous
explosion.

### 3. Fleet pace-up as one variable

The acceleration of the alien march as you kill them is one of
the iconic feels of Space Invaders. The Frame version is one
domain variable, recomputed once per kill. Plain GDScript would
either centralize it (doable) or scatter it (more likely under
deadline pressure).

---

## What Frame demonstrably *didn't* help with

### 1. Bullet management

The driver maintains the bullet array. Frame doesn't help with
"this bullet is at (x, y), check collision with every alive
invader." That's collision math, not state.

### 2. Render loop

Drawing the alien grid, animating the swap between standard and
"second pose" sprites, the explosion particles — all driver-side.
No FSM helps with that.

---

## Comparison: hypothetical Invaders in plain GDScript

- `Player`: enum + `match` + per-state timers as instance vars.
  ~80 lines. Frame's `$.timer` reset-on-entry would need a manual
  reset on every state change in GDScript.
- `Fleet`: array of bools + `_update_pace()` as a method, all
  driven by a state enum + `match`. ~120 lines, equivalent.
- `Invaders`: orchestrator with `match top_level_state` and a
  manual "if currently in any of $Playing/PlayerDying/WaveComplete:
  handle pause" — that last bit is the HSM cost paying off in
  Frame. In GDScript you'd compose with a helper function or live
  with the duplicated handling.

**Net:** Frame is a clear win on the HSM piece, equivalent on
the others. The HSM saves the duplicate-`if pause_pressed`
handling across three states, which is the chapter's stated
teaching point.

---

## When to reach for Frame for an Invaders-class game

**Use Frame when:**
- Two or more game-states share a piece of behavior (pause,
  draw, query). Lift it to an HSM parent.
- A timed sub-state needs fresh timer data on every entry.
- The pacing of the game depends on a derived variable that
  should be computed in one place, not scattered.

**Don't reach for Frame when:**
- The game is one mode and time is uniform.
- You're scared of HSMs. (They're not as scary as the syntax
  looks; this chapter is the right place to grok it.)

For Invaders: yes — first chapter where HSM matters, and the
"three children share pause" payoff is concrete.
