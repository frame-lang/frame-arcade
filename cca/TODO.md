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

### Witt's End probability gate (canon-fidelity) — **DONE 2026-05-08**

Wired in commit pending: 9 `probability` GATES at `108:east/north/
south/ne/nw/se/sw/up/down` with `pct=95`, plus the always-bumper
at `108:west` for the cave-in message. Driver rolls once per
attempt in the bumper-key dispatch (deliberately not re-rolled in
`_handle_movement` to avoid compounding the probability). Removed
the port-only `108:north → 67` walking shortcut. Architectural
probe updated; conformance back to 50/50.

Test: `tests/test_cca_witts_end.gd` rolls 1000 east attempts under
a pinned RNG seed and asserts the distribution is within ±25 of
canon 95/5 — observed 51 escapes / 949 bounces.

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
