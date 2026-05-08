# CCA — TODO

Pending non-canon work. Canon-fidelity gaps live in
[`CANON_DELTAS.md`](CANON_DELTAS.md) and the conditional-row
dashboard ([`tests/test_cca_conditional.gd`](tests/test_cca_conditional.gd)).

---

## Open

### Crowther / Woods credit splash screen

When CCA launches (either as the standalone `cca/godot/` build or
from the arcade cabinet's chapter list), display a credit splash
before the *"You are standing at the end of a road..."* opening:

> **COLOSSAL CAVE ADVENTURE**
>
> Originally created by **Will Crowther** (1976) and expanded by
> **Don Woods** (1977) at the Stanford Artificial Intelligence
> Laboratory. The 350-point release — the canonical version this
> port follows — is preserved at the IF Archive as a public-domain
> historical artifact.
>
> *This Frame state-machine implementation is a faithful re-port
> of the 1977 PDP-10 FORTRAN source ([`canon/advent.for`](canon/advent.for))
> retrieved from the IF Archive. Every gameplay decision either
> traces to the canon or is documented as a deliberate divergence
> in [`CANON_DELTAS.md`](CANON_DELTAS.md).*
>
> Press any key to enter the cave.

Implementation notes:

- One screen, ~five seconds, dismissable on any keypress.
- Standalone build: shows on first launch only; subsequent
  launches go straight to the prompt.
- Arcade build: shows every time CCA is selected from the cabinet
  menu — the cabinet is presented to the player as "this chapter,"
  not "the game," so Crowther/Woods get credited per session.
- Background: maybe an ASCII rendering of the cave's well-house
  text or a static image of a stalactite. Avoid emoji / contemporary
  iconography; this is a 1977 game and the credit screen should feel
  appropriate to the era.
- The standalone splash should also link the IF Archive URL
  (`https://www.ifarchive.org/if-archive/games/source/advent-original.tar.gz`)
  so anyone curious about the original source can find it.

Lives in: a new scene `godot/scenes/credits.tscn` + script
`godot/scripts/credits.gd`. Wire from `driver.gd` `_ready()`.

---

### Witt's End probability gate (canon-fidelity)

Currently the port has `108:east → 106` as an unconditional
walking corridor. Canon (`advent.dat` row `108 95556 ...`) gives
every direction *except west* a 95% chance of bouncing back with
canon msg #56 ("you have crawled around in some little holes and
wound up back in the main passage"). Only on the 5% fail does
EAST actually walk to canon 106; WEST always prints msg #126.

The faithful implementation:

- New `"check": "probability"` GATES type at `108:north/south/...`
- The check inspects a probability percent in the gate value
- Driver rolls `randi() % 100 < pct`; on success emits the bounce
  message and stays put; on fail falls through to the topology dest

This is the next canon-completion target. Implementation pattern
mirrors the rusty-door work: extend GATES, extend the driver gate
chain, sync the arcade mirror, add a focused test.

The current `_probe_no_108_corridor` in `test_cca_canon.gd` should
be revised to acknowledge that canon does have `e → 106` (just
probabilistically), and refocus on the port-only `108:north → 67`
shortcut as the actual deviation.

---

### Probabilistic maze decoration (canon rooms 5, 65, 66, 108, 111)

Canon's "twisty maze" rooms scramble compass directions to defeat
mapping. Each maze room has 9-10 exits with carefully randomised
destinations. Port currently uses simplified linear topology.
Real canon-fidelity here is a week's project for cosmetic effect.
Defer indefinitely.

---

## Closed (in this codebase)

(The full delta inventory is in [`CANON_DELTAS.md`](CANON_DELTAS.md);
this section just notes session-level milestones.)

- 2026-05 — per-room canon topology rebuild, 140/140 rooms aligned.
- 2026-05 — troll-bridge crossing 117↔122 added.
- 2026-05 — fissure-crossing aliases (OVER/ACROSS/WEST/CROSS)
  + bumper messages for JUMP/SLIT/etc.
- 2026-05 — Treasure.$Vanished.reappear restored (eggs come back via
  FEE FIE FOE FOO from the troll's pocket).
- 2026-05 — dark-room pit-fall hazard implemented (canon msg #16
  warning, 35% pit-fall on subsequent attempts).
- 2026-05 — death-message rooms 20/21 fire `player.die()` with
  canon prose.
- 2026-05 — clam/oyster squeeze gate at canon 103.
- 2026-05 — rusty-door puzzle at canon 94 wired end-to-end.
- 2026-05 — `19:sw → 74` dragon-canyon shortcut alias.
- 2026-05 — fetched canonical 1977 FORTRAN source (`advent.for`)
  from IF Archive; `gen_locations.py` decoder validated against
  `advent.for` lines 105-122 specification.
