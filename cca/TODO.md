# CCA — TODO

Pending non-canon work. Canon-fidelity gaps live in
[`CANON_DELTAS.md`](CANON_DELTAS.md) and the conditional-row
dashboard ([`tests/test_cca_conditional.gd`](tests/test_cca_conditional.gd)).

---

## Open

### Crowther / Woods credit splash screen — **DONE 2026-05-08**

Implemented as the welcome panel in `Driver._print_welcome` (and
the byte-equivalent mirror in `arcade/godot/scripts/cca_main.gd`).
Every CCA session opens with explicit attribution to the original
1976/77 work before any game prose, then the regular `> ` prompt
takes over. Era-appropriate plain text, no emoji, era-appropriate
amber palette.

The splash names:
- Will Crowther (1976) and Don Woods (1977) by full name
- Stanford AI Lab as the institutional context
- The PDP-10 FORTRAN-IV source as the canon provenance
- The Interactive Fiction Archive as the preservation venue
- Public-domain historical record as the licensing posture

Test: `tests/test_cca_credit_splash.gd` exercises ten content
checks (title, both names, both years, Stanford, FORTRAN
provenance, IF Archive, public-domain, HELP hint) using the
captured-driver pattern. All ten pass.

Future polish (not blocking): a literal first-launch-only flag
(currently the welcome shows every session), an ASCII-art
well-house header, and a clickable IF Archive URL.

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
