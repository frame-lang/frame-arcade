# CCA — TODO

Pending non-canon work. **The authoritative canon-fidelity status
post-V1 is now [`V1_REVIEW.md`](V1_REVIEW.md)**, with the
architectural follow-on tracked in [`V1_2_PLAN.md`](V1_2_PLAN.md).
The pre-V1 planning docs (`CANON_FULL_AUDIT.md`,
`CANON_FULL_PLAN.md`, `CANON_DELTAS.md`) were archived to
[`docs/historical/`](docs/historical/) in V1.2 as historical record;
the live coverage probe at
[`tests/test_cca_conditional.gd`](tests/test_cca_conditional.gd)
remains in-place.

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

### Gold-blocks-the-steps puzzle (canon row `15 150022 …`) — **DONE 2026-05-08**

Implemented via a new `carrying` gate type with two flavours:
`msg`-only (print canon prose, stay put) and `dest`-only
(walk to a destination room, where its own death handler
fires). 6 gates at canon 15 (UP/EAST/PIT/STEPS/DOME/PASSAGE)
emit "The dome is unclimbable." while carrying gold.

Test: `tests/test_cca_gold_blocks_steps.gd` exercises four
phases (blocked verbs with gold, free verbs with gold,
walk without gold, drop+walk recovery). Companion canon
test `tests/test_cca_gold_falls_pit.gd` exercises the canon
14:150020 fall-to-death pair.

Canonical playthrough rewritten so bird+snake clearance now
precedes gold pickup; gold retrieval uses the canon long-way
(19→east→15→south→18→take gold→15→down→19→north→28→33).
52 stages still green.

---

### Gold-falls-pit death (canon row `14 150020 …`) — **DONE 2026-05-08**

Companion to gold-blocks-the-steps. Canon 14 DOWN/PIT/STEPS
while carrying gold dump the player into canon 20 (broken-
neck pit-bottom death) where the existing room-entry death
handler fires. Test exercises with-gold deaths via DOWN/
PIT/STEPS, without-gold normal walk to 15, and drop+walk.

---

### Probabilistic maze decoration (canon rooms 5, 65, 66, 111) — **DONE 2026-05-08**

The canon section-3 probability rows (`5 50005 …` 50% self-loop at
forest, `65 80556 …` 80% bumper at Bedquilt, `66 …` at Swiss Cheese,
`111 …` at top of stalactite) are wired as GATES chains in
`topology.gd` and exercised by `tests/test_cca_maze_decoration.gd`.
22 distribution checks at 1000 rolls each, all within tolerance of
canon percentages.

The first maze proper ("twisty little passages, all alike", canon
50-57) and the second maze ("twisty passages, all different", canon
131-139) are encoded room-by-room with explicit `advent.dat`
citations in `topology.gd`. The classic mark-rooms-with-dropped-items
puzzle works.

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
- 2026-05 — Witt's End 95/5 probability gate (canon 108).
- 2026-05 — Crowther/Woods credit splash on every session.
- 2026-05 — gold-blocks-the-steps + gold-falls-pit pair
  (canon rows 15:150022 + 14:150020); canonical playthrough
  reordered to bird→snake→gold; conditional-row coverage
  43→44/62.

---

## Open — Player UX

### Driver: `"exit"` → `"quit"` mapping is surprising — **DONE 2026-05-17**

Dropped the `"exit": "quit"` synonym from both driver.gd and
cca_main.gd. Players quit via `quit` / `q`. Typing `exit` at a
room with an "exit" key in topology walks via that exit;
otherwise falls through to "I don't know that word." Replaced
with an inline NOTE comment explaining the canon-vs-modern-UX
tradeoff so a future reader sees why the mapping was removed.

### Driver: LineEdit loses focus during gameplay — **DONE 2026-05-17**

Root cause: synchronous `input.grab_focus()` in
`cca_main.gd:_hide_exit_dialog` and both drivers' `_notification`
focus-in handlers. Per the comment already in `_on_text_submitted`,
synchronous grab inside an _input signal handler doesn't stick on
every Godot 4.x version — the deferred version does.

Switched both regrab sites to `input.call_deferred("grab_focus")`,
matching the working pattern already used after text submit.
Verified the Y/N prompt and F5/F9 paths weren't the culprit —
those flow back through `_on_text_submitted`'s deferred regrab.

(For reference, the original investigation hypotheses:)
command sequence loses focus), then targeted fix.
