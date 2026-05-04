# Side-Scrolling Shooter: an honest evaluation

**Question:** Can Frame handle a multi-phase boss + many enemies
+ wave scheduling without the orchestrator becoming a swamp?

**TL;DR:** Frame is **a 5/5 win for Shooter** — the full toolkit
shows up at once: HSM (Boss with 3 phases × 2 leaves each), a
parameterized × N enemy system at scale (waves spawn batches of
Enemy(kind, hp, fire_rate, points)), and an orchestrator that
threads enemy ticks, wave scheduling, and boss-fight transition.
The Boss's 3-phase HSM is the showpiece — each phase has its own
firing pattern (single shot, spread, spray) and its own HP
threshold for transition to the next.

This chapter also surfaced a chapter-source bug: a
`self.boss_spawned` typo (correct field: `boss_spawn_pending`)
that the smoke test caught. Fixed in commit `ab347cd`.

---

## What was built

- `Player` — same lifecycle as Invaders ch.3.
- `Enemy(kind, hp, fire_rate, points)` — parameterized × many,
  4-state lifecycle ($Spawning → $Active → $Dying → $Gone).
- `Boss` — multi-phase HSM with $PhaseOne / $PhaseTwo /
  $PhaseThree parents, each with $PXIdle / $PXFiring leaves.
  Each phase has its own firing mode.
- `Shooter` — orchestrator with $Attract / $Playing / $BossFight
  / $Victory / $GameOver lifecycle.

**Frame source:** ~810 lines (the largest chapter)
**Generated GDScript:** ~3000 lines
**Driver:** ~1300 lines
**Smoke tests:** 40 checks covering all four FSMs + boss phase
transitions + wave-spawn → boss-fight transition.

---

## Per-system Frame value scoring

| System | Score | Why |
|---|---|---|
| `Player` | **3** | Same shape as Invaders' Player. By chapter 7 the pattern is familiar; the system here is reused, not re-introduced. |
| `Enemy` | **4** | Parameterized × N at scale. Each enemy has its own kind, hp, fire_rate, points — set once at construction, no per-frame allocation. The 4-state lifecycle is correct (spawning has an entrance animation; dying has a death animation; gone is reaped). The chapter spawns ~50 enemies across waves; the parameterization shape scales naturally. |
| `Boss` | **5** | Three-phase HSM with parent states owning shared damage handling. Each phase has its own firing leaf with its own duration timer. Crossing 66% HP transitions PhaseOne → PhaseTwo (fires spread shot); crossing 33% transitions to PhaseThree (fires spray); 0 HP → $Dying → $Gone. The shape Frame is best at: behavior that genuinely changes by phase, with HP-driven thresholds. |
| `Shooter` | **5** | Orchestrator that threads everything: ticks player + each enemy + boss; advances wave_timer; checks waves_spawned >= waves_before_boss to trigger $BossFight; checks player.dead to trigger $GameOver; checks boss.is_gone to trigger $Victory. The orchestrator pattern at its biggest in the arcade (CCA's is bigger still). |

---

## What Frame demonstrably did well

### 1. Boss multi-phase HSM

Each phase is a parent state with shared damage-handling. The
phase-1 idle and phase-1 firing children inherit damage logic
from `$PhaseOne`. The transition to phase 2 happens *inside*
`$PhaseOne.hit()` based on HP threshold — the parent owns the
phase-progression decision. Children only handle their own
timing (idle → firing → idle).

If you wanted a phase-4 "death throes" with different damage
behavior, you'd add `$PhaseFour { hit() {...} } -> $Dying` and
two firing leaves. No surgery to existing phases.

### 2. Parameterized enemies + scale

Spawning a wave is "construct N Enemy instances with the right
params, append them to the orchestrator's array, the orchestrator
ticks them all." 50 enemies is no different from 5 — same
serialization shape under @@[persist] (cabinet adds this), same
orchestrator if-ladder (per-name dispatch).

### 3. The wave-then-boss transition

`$Playing.tick()` checks `waves_spawned >= waves_before_boss`
and transitions to `$BossFight`. The boss spawn happens in
`$BossFight.$>` (entry handler). The transition is one line; the
state machine guarantees it fires exactly once per game.

---

## What Frame demonstrably *didn't* help with

### 1. Bullet management (player + enemy + boss)

Three separate bullet arrays, each with positions/velocities/
collision checks. Driver-side. The FSM tells the driver
"this enemy wants to fire" via `wants_to_fire_single()` etc.;
the driver spawns the actual bullet entities.

### 2. Particle effects

Boss explosion, enemy death sparks, hit flashes — all driver-side.

### 3. Wave content design

The driver decides what enemies are in wave N (small fast ones
in early waves, bigger tougher ones later). Frame doesn't model
content; the orchestrator just advances waves_spawned.

---

## Comparison: hypothetical Shooter in plain GDScript

The Boss multi-phase is the part where Frame is clearly better.
Plain GDScript:

```gdscript
var boss_phase: int = 1
var boss_hp: int

func boss_take_damage(dmg: int):
    boss_hp -= dmg
    match boss_phase:
        1:
            if boss_hp <= hp_start * 0.66:
                boss_phase = 2
                _enter_phase_two()
        2:
            if boss_hp <= hp_start * 0.33:
                boss_phase = 3
                _enter_phase_three()
        3:
            if boss_hp <= 0:
                boss_phase = 0
                _enter_dying()
```

Plus separate timers for each phase's firing pattern. Plus
phase-transition handlers. Plus phase-aware drawing. The Frame
version isolates each phase's behavior in its own state, with
the parent owning the threshold-transition logic.

The other systems are equivalent in plain GDScript — Player
(enum + match), Enemy (instances of a class), Shooter
(orchestrator with match) all work fine. Frame's win is
concentrated in Boss.

---

## When to reach for Frame for a Shooter-class game

**Use Frame when:**
- The boss has 3+ genuinely-distinct phases with different
  attack patterns.
- Enemy variety is parameterized (kind, stats) rather than
  per-class.
- Wave scheduling has multiple modes (waves vs boss vs victory)
  and the transitions need to be exact (no "did we already spawn
  the boss?" boolean flags).

**Don't reach for Frame when:**
- The boss is single-phase. A single state machine is overkill
  for "enemy with HP."
- You only have one enemy type. A class is fine.

For Shooter: yes — full toolkit at scale.
