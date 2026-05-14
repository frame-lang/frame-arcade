# 100% canon implementation plan

Companion to `CANON_FULL_AUDIT.md`. Every 🟡 and 🔴 entry from the
audit is sequenced here, with dependency order, expected effort, and
the test that would prove canon parity.

**Ground rule**: no item is deferred without explicit user sign-off.
The two ⚪ items at the end of this plan call out the exact deferral
decision and ask for confirmation.

**Sequencing principle**: build from machinery → mechanics → flavor.
Each phase strictly unlocks the next. No phase is started until the
prior phase is green.

---

## Phase 0 — pre-flight (ALREADY LANDED)

These are already in the codebase as of the audit doc:

- ✓ Per-room canon topology (140/140 rooms)
- ✓ Conditional dashboard (44/62 covered)
- ✓ Witt's End 95/5 probability gate
- ✓ Gold-blocks-the-steps gate (canon 15)
- ✓ Gold-falls-pit gate (canon 14)
- ✓ Crowther/Woods credit splash
- ✓ 34/34 tests passing

---

## Phase 1 — mechanism extensions (foundation work)

These extend the gate-handling and aspect-bus machinery so subsequent
phases have hooks to plug into. Without these, later phases can't be
implemented cleanly.

### 1a. Generalize the carrying-gate to support `here-or-carrying`

**Canon row example**: `19 211032 49` (SW @ 19 if snake here-or-carried → 32).

**Work**:
- Add `here_or_carrying` check type to `topology.gd` GATES handler.
- Same `obj` field; check `fsm.player.carrying(obj_id) OR object_at(obj_id, current_room)`.

**Test**: extend `test_cca_topology.gd` whitelist + add focused test
that walks a snake-carrying scenario.

**Unblocks**: rows 19:sw, 117:over/across/cross/ne, 122:over/across/cross/sw.

### 1b. Generalize the gate-with-dest pattern to the `prop-not-N` family

**Canon rows**: 17:forward (prop != 1 → 21), 27:forward (mirror), 69:south (dragon != 0 → 120), 74:west (mirror), 117:jump (chasm != 0 → 21).

**Work**:
- Add `prop_not_n` check type to GATES with fields `obj`, `prop_test`,
  optional `dest`/`msg`.
- Resolves obj → prop reader (via FSM aspect proxy or per-object accessor).

**Test**: focused tests for fissure-forward (with/without bridge),
dragon-killed shortcut.

**Unblocks**: ~10 rows in §1.3 of audit.

### 1c. Probabilistic motion gate type

**Canon rows**: 19:sw 35%, 65:* 50/60/75/80%, 66:* 50/80%, 111:* 40/50%.

**Work**:
- Extend `probability` gate to support `dest` (where to walk on hit)
  in addition to `msg` (already supported for Witt's End).
- Multiple-row scan: when a probability roll fails, look for a fallback
  row with same room/verb but different M; that becomes the next probe.
- Implement as ordered list under the gate-key, not single dict.

**Test**: focused test for room 65 SOUTH with pinned RNG: 80% loop
back vs 20% no-exit.

**Unblocks**: probabilistic-maze decoration phase 5.

### 1d. Forbidden-to-dwarves verb gate

**Canon row**: `61 100107 46` (SOUTH @ 61, M=100).

**Work**:
- Add a `forbidden_to_dwarves` flag on topology rows so the dwarf-AI
  random-walk filter respects it.
- Canon: dwarves can't follow the player into 107 because the
  travel-table M=100 forbids dwarves from using that motion.

**Test**: dwarf can't reach canon 107 even after player walks there.

**Unblocks**: row 61:south (and any future M=100 rows).

### 1e. Add IWEST counter for the "WEST" snark

**Canon**: 10th time player types "WEST" instead of "W" → msg #17.

**Work**:
- Add `iwest_count` to driver state.
- Increment on each "WEST" input. On 10th: print msg #17.
- Persist via Frame `@@[persist]`? Or driver-only? Decide.

**Test**: type WEST 10 times, assert msg #17 fires once.

### 1f. Add KNFLOC tracking

**Canon**: knife-on-floor counter; -1 = "you've been warned about
ignoring the knife"; 0 = no knife; >0 = knife in this room (after a
miss). Drives canon msg #116 ("with what?  your bare hands?" — a
flavor variant when player attempts to pick up a knife).

**Work**:
- Add `knfloc` to driver or Adventure state.
- Wire into dwarf knife-throw misses (set to LOC).
- Wire into TAKE handler: if player tries to take "knife" and `KNFLOC == LOC`, fire msg #116 and set `KNFLOC = -1` permanently.

**Test**: dwarf throws knife (miss); player types "TAKE KNIFE" → msg #116.

---

## Phase 2 — close every conditional row in §1.3 of the audit

With Phase 1 mechanisms in place, walk every conditional row from
the audit one-by-one.

### 2a. Fissure forward routes to room 21 (death) without bridge

**Rows**: 17 412021, 27 412021.

**Work**:
- Add `prop_not_n` gate for `17:forward` with dest=21 (which is the
  death room "you didn't make it").
- Mirror at `27:forward`.
- Verify room 21 entry handler in `cca.fgd` `_verb_move` already
  fires `player.die()` (it should, per the existing canon-20/21 patch).

**Test**: focused — at room 17 with no bridge, FORWARD → die.

### 2b. Dragon-killed shortcut: 69:south → 120, 74:west → 120

**Rows**: 69 331120, 74 331120.

**Work**:
- Use `prop_not_n` gate (dragon-prop != 0 means dragon-killed).
- Walk player to 120 (the connecting canyon).
- Verify topology row 120 exists and has connectivity.

**Test**: kill dragon at 119, then walk back via 69:south or 74:west.

### 2c. Plover-emerald drop (routine 302)

**Rows**: 33 159302 (PLOVER), 100 159302.

**Work**:
- Modify `MagicWordTeleport.handle("plover")`:
  - At canon 33 carrying emerald: drop emerald at 33, then re-attempt
    PLOVER (will route to plover squeeze 301, fail because emerald
    is now at 33, player teleports without the emerald).
  - Result: player at canon 100 without emerald; must use squeeze
    99→100 to retrieve it.

**Test**: player carrying emerald at 33 says PLOVER; verify emerald
dropped at 33 and player at 100.

### 2d. Snake-here-or-carrying SW from 19 → 32

**Row**: 19 211032 49.

**Work**: use `here_or_carrying` gate from Phase 1a.

**Test**: SW from 19 with snake present (before bird drives it away)
→ snake-block bouncer at 32. Snake gone → 35% prob to 74.

### 2e. Troll-here gate at 117/122 (replace "blocking" check)

**Rows**: 117 233660, 122 233660.

**Work**: refactor `troll.is_blocking_bridge()` to use canon's
here-or-carrying semantics (via `here_or_carrying` from Phase 1a).

**Test**: existing test_cca_troll should still pass; add coverage
for "drop troll" edge case (canon allows toting troll).

### 2f. Chasm-prop gate at 117 (post-bear)

**Row**: 117 332661 (OVER), 117 332021 (JUMP).

**Work**: separate Chasm prop from CrystalBridge; wire `prop_not_n`
gate with chasm-collapsed condition.

**Test**: after bear-falls-bridge sequence, OVER prints msg #161 and
JUMP routes to room 21 (death).

---

## Phase 3 — close every probabilistic row

After Phase 1c machinery is in place.

### 3a. 19:sw 35% probability shortcut

**Row**: `19 35074 49`.

**Work**: replace unconditional `19:sw → 74` with `probability` gate
pct=35; on miss, fall through to `19:sw 211032` (snake-here-or-carry
gate from Phase 2d).

**Test**: 1000 SW attempts under pinned seed → ~350 reach 74,
~650 hit snake bouncer (or no-exit).

### 3b. Bedquilt (canon 65) probabilistic walks

**Rows**: 6 rows at 65 covering S/UP/N/DOWN with multiple probabilities.

**Work**:
- For each verb, create an ordered list of probability rolls:
  - 65:south → 80% msg#56 / fall-through (no row → "can't go south")
  - 65:up → 80% msg#56 / 50% room 70 / fall-through
  - 65:north → 60% msg#56 / 75% room 72 / fall-through
  - 65:down → 80% msg#56 / fall-through
- Implementation: gate type `probability_chain` that walks the list
  in order, rolling each probability; first hit wins.

**Test**: 1000 attempts per verb → expected distribution (within ±3σ).

### 3c. Swiss Cheese Room (canon 66) probabilistic walks

**Rows**: 66:south 80% msg#56, 66:nw 50% msg#56.

**Work**: same pattern as 65.

### 3d. Twisty Passage (canon 111) probabilistic walks

**Rows**: 111:down/jump/climb 40%→50, 111:down 50%→53.

### 3e. Forest random walk (canon 5)

**Row**: 5:forest/forward/north 50% → 5 (loop).

**Work**: probability gate that loops in place 50% of the time.

**Test**: 100 north attempts at 5 → ~50 stay at 5, ~50 walk to canon
6 (per topology row 5).

---

## Phase 4 — vocabulary / verb completeness

### 4a. Implement missing action verbs

| Verb | Implementation | Reference |
|---|---|---|
| FIND | walk to TARGET if same loc; else default msg #59 | advent.for STMT 9190 |
| BRIEF | set `abbnum=10000` (suppress long descs after first) | STMT 8260 |
| RUB | "rubbing isn't productive" msg #76 unless lamp | STMT 9160 |
| WAKE | endgame penalty (only at CLOSED) | STMT 9290 |
| BLAST | endgame BONUS-set + 20000 jump | STMT 9230 |
| SAY (echo) | "Okay, X" for non-magic words | STMT 9030 |
| HOURS | ⚪ pending sign-off | STMT 8310 |

### 4b. Implement missing object words

| Object | Implementation |
|---|---|
| TABLET (13) | New Item at canon 101; READ TABLET → msg #196 |
| MIRROR (23) | New Item at canon 109/two-place 116; BREAK MIRROR endgame penalty |
| PHONY PLANT (25) | Flavor at canon 23/67 (twopit); only visible when plant is tall |
| STALACTITE (26) | Flavor (alternate maze route, low priority) |
| SHADOWY FIGURE (27) | Flavor at canon 35/110 |
| MESSAGE (36) | At canon 140 (second-maze dead end); pirate moves to MESSAG.PLACE = CHLOC2 |
| VOLCANO (37) | Flavor at canon 126 |
| CARPET/MOSS (40) | Flavor at canon 96 |
| CAVE DRAWINGS (29) | Flavor at canon 97 |

The "flavor" objects only require descriptions in the room text and
EXAMINE handlers — minimal mechanical work.

### 4c. Action default messages

For every verb in §8 of the audit marked 🟡/🔴, wire the canon
default message via the verb's `ACTSPK[VERB]` index.

---

## Phase 5 — message text / prose alignment

For the ~20 🟡/🔴 messages in §6 of the audit:

### 5a. Random "I don't understand" variants

20% chance msg #60, 20% msg #61, otherwise msg #13.

Work: `driver.gd` `_process_input` unrecognized verb path.

### 5b. Forced quit when wandered out with dead lamp

Canon msg #185 when LIMIT<0 AND LOC<=8.

### 5c. Death taunt + resurrection message pairs

Map port resurrection prompt to canon msg #81/83/85/87/89 (taunt) and
#82/84/86/88/90 (rebirth).

### 5d. Other concrete prose gaps (per §6 audit)

- msg #2 (dwarf blocks way) — wire to dwarf-block movement check.
- msg #8 (PLUGH whisper at Y2 25%) — `_process_input` post-room-print roll.
- msg #15 (LOOK detail counter) — driver state.
- msg #91 / #140 (BACK fallback messages).
- msg #11 (in/out ambiguity) — ENTER X with X != stream/water.
- msg #70 (feet wet) — at water rooms.
- msg #71 (don't have appetite) — EAT bird/snake/etc.
- msg #76 (rubbing not productive).
- msg #110 (drink-not-water).
- msg #116 (knife caveat) — Phase 1f.
- msg #127 (rustling sounds) — pirate AI.
- msg #136 (disturbed dwarves) — endgame penalty.
- msg #137/138/154/156/158/164/182/186/191/192/193/194/196/197/199 — assorted.

---

## Phase 6 — NPC AI completeness

### 6a. Dwarf knife-throw probability ramp

Canon: `RAN(1000) < 95*(DFLAG-2)` for hit.

DFLAG=2: 0% (first set always misses)
DFLAG=3: 9.5%
DFLAG=4: 19%
DFLAG=20 (impostor): 171% capped at near-100%

Port currently has flat probability — replace with ramp.

### 6b. Dwarf blocks player exit (msg #2)

Canon STMT 71: if dwarf has seen player AND came from `NEWLOC`,
force player to stay at `LOC`, fire msg #2.

### 6c. FEED dwarf → DFLAG anger increment (msg #103)

### 6d. Throw axe at troll (msg #158)

Canon: troll catches axe with msg #158. Currently port's THROW handler
doesn't differentiate the troll case.

### 6e. Drop bird at dragon (msg #154 + bird vaporized)

Canon: bird flies into dragon's mouth, gets disintegrated.

### 6f. Throw axe at bear (msg #164 + axe stuck)

### 6g. Pirate stash announcement (msg #186)

Canon: `TALLY==TALLY2+1 AND chest only outstanding AND lamp here lit`
→ msg #186 fires (one-shot directional hint pointing toward pirate's
stash).

### 6h. Dragon kill: move dragon + player to canon 120

Canon: ATTACK dragon → YES → dragon moves to 120, rug moves there,
player teleported there, room re-described.

Currently port's dragon-kill mutates state but doesn't relocate.

### 6i. Pirate-forbidden room set match canon 18 rooms

Canon: 46, 47, 48, 54, 56, 58, 82, 85, 86, 122, 123, 124, 125, 126, 127, 128, 129, 130.

Port's pirate-forbidden list needs to match exactly.

---

## Phase 7 — endgame completeness

### 7a. Repository setup (canon STMT 11000)

Match the exact object set placed at 115/116:
- 115: bottle (empty), plant, oyster, lamp, rod, dwarves, mirror.
- 116: grate, snake, bird (caged), rod2, pillow, mirror2.

### 7b. Mirror as canon object 23

Add MIRROR Item, two-placed at 109/116. BREAK MIRROR at endgame fires
msg #197 + dwarf-wake death penalty.

### 7c. BLAST verb (canon STMT 9230)

- ROD2 prop becomes "dynamite" only after CLOSED.
- BLAST rod2-not-here: msg #54.
- BLAST at LOC=115 + rod2-not-here: BONUS=134, +30 score.
- BLAST with rod2 here: BONUS=135, +25.
- BLAST elsewhere: BONUS=133, +45.
- All trigger 20000 (final score).

### 7d. PANIC timer cap

When player tries to leave during closing: `CLOCK2 = MIN(CLOCK2, 15)`.

### 7e. Wandered-out forced quit (msg #185)

`LIMIT<0 AND LOC<=8` → forced quit.

### 7f. WAKE the dwarves (canon STMT 9290)

Only at CLOSED: msg #199, GOTO 19000 (death).

### 7g. Mirror break = dwarf wake (canon STMT 9280)

Only at CLOSED: msg #197, GOTO 19000.

---

## Phase 8 — scoring math alignment

Tally must hit 350 max. Per audit §15:

- Treasure values: 12 / 14 / 16 by canon position (with 2 each for
  found).
- Survival, didn't-quit, got-into-cave, reached-endgame, BLAST bonus
  components — match canon weights exactly.
- Witt's End magazine bonus: ✓ already.
- Round-off: +2 always.
- Hint penalty: subtract per-hint cost ✓ already.

After Phase 7d completes, recompute MXSCOR; should be 350.

---

## Phase 9 — BACK + random nav + LOOK polish

### 9a. BACK verb

Canon: walk OLDLOC (or OLDLC2 if OLDLOC was forced). If no path,
msg #140. If trying to BACK from where you are, msg #91.

### 9b. LOOK detail counter (msg #15)

3 LOOK calls then suppress; reset on movement.

### 9c. CAVE verb

Outdoors → msg #57; indoors → msg #58.

### 9d. ENTER STREAM/WATER → msg #70

### 9e. ENTER X (non-stream) → re-dispatch

Already partially handled; verify completeness.

### 9f. Plant-PLANT2 prop sync

When PLANT prop advances, PLANT2 prop = PLANT/2.

### 9g. Witt's End hint #9 — DON'T GO WEST text

Already implemented; verify the trigger turns and cost.

### 9h. Hint trigger thresholds

Verify all 6 hints use canon trigger turns (4/5/8/75/25/20) and costs
(2/2/2/4/5/3).

### 9i. Hint LIMIT bonus

Per accepted hint: `LIMIT += 30 * cost`.

### 9j. Verbose-instructions LIMIT bonus

If HINTED(3) at startup: `LIMIT = 1000` instead of 330.

---

## Phase 10 — flavor and polish

### 10a. Hollow voice "PLUGH" at Y2 (25% per visit)

### 10b. Treasure-elusive lamp cap

If `TALLY == TALLY2 != 0`: `LIMIT = MIN(LIMIT, 35)`.

### 10c. Dwarf alternate spawn (DALTLC=18)

If a dwarf would init on top of the player, spawn at 18 instead.

### 10d. First-encounter dwarf-killing roll

50% chance per dwarf to be removed pre-encounter (unless save-restored,
in which case all 5 spawn).

### 10e. Inventory description ordering

Canon `JUGGLE` makes the most-recently-relevant object appear first
in room descriptions. Port may or may not match.

### 10f. ABB long-vs-short description cycle

Every 5 visits to a room, force long description.

### 10g. Read-the-tablet at canon 101 (msg #196)

### 10h. Oyster-clue chain (msgs #192/#193/#194)

At endgame, READ OYSTER cycles: ask Y/N, on Y print one of the chain
messages; HINTED(2) tracks state.

### 10i. Phony plant flavor at canon 23/67

When player at twopit room with plant tall: see phony plant instead
of regular plant text.

### 10j. Cave drawings at canon 97 (flavor)

EXAMINE → flavor text.

### 10k. Volcano flavor at canon 126

Already lit per COND bit 0; canon flavor in description.

### 10l. Carpet/moss at canon 96 (flavor)

---

## Phase 11 — PDP-10-specific items (PENDING USER SIGN-OFF)

These remain ⚪ unless the user confirms they're out of scope.

### 11a. HOURS verb

Canon: print prime-time schedule. PDP-10 timesharing only.

**Recommendation**: scope-out for Godot port. The Frame Adventure
runs on a single-user desktop; "prime time gating" has no analog.

**Sign-off needed**: confirm scope-out.

### 11b. SUSPEND latency (45-min restart wait)

Canon: SAVE writes a timestamp; RESTORE refuses if less than `LATNCY`
minutes have passed (45 default).

**Recommendation**: scope-out. Port's save/restore is instantaneous —
canon's latency was an anti-cheating measure on a multi-user system.

**Sign-off needed**: confirm scope-out.

### 11c. Demo-game mode (turn-limited)

Canon: prime-time non-wizards get a short demo game.

**Recommendation**: scope-out (single-user implies always-full game).

**Sign-off needed**: confirm scope-out.

---

## Phase 12 — verification & sign-off

### 12a. Update conditional dashboard expectations

Target: 62/62 covered (currently 44/62).

### 12b. Update test_cca_canon.gd dashboard

Currently 38/38 architectural-conformance checks; expand to cover the
Phase 6 NPC AI changes and Phase 7 endgame BLAST.

### 12c. End-to-end win path test

`test_cca_canonical.gd` already runs init → won in 52 stages. After
all phases land, verify the path still hits 350 max points (with
no hints accepted).

### 12d. Negative-space tests

For each canon mechanic, test the "wrong" path:
- Take gold via 14:down → die.
- Take gold via 15:up → bumper.
- ATTACK SNAKE → futile.
- ATTACK DRAGON without YES → no kill.
- BREAK MIRROR before CLOSED → no-op.
- BLAST without dynamite → "OK".

### 12e. Canon-prose audit

Walk every canon msg # in §6 of the audit; verify the port's
output matches verbatim (case-insensitive). This is the highest-cost
verification step but the only one that catches subtle prose drift.

---

## Effort estimate (rough)

| Phase | Items | Effort |
|---|---|---|
| 1 (machinery) | 6 | 1-2 days |
| 2 (conditional rows) | 6 | 1-2 days |
| 3 (probabilistic) | 5 | 1 day |
| 4 (vocab/verbs) | 3 sub-phases | 2-3 days |
| 5 (prose alignment) | 4 sub-phases | 1-2 days |
| 6 (NPC AI) | 9 | 2-3 days |
| 7 (endgame) | 7 | 2 days |
| 8 (scoring) | 1 | half day |
| 9 (BACK + nav) | 10 | 1-2 days |
| 10 (flavor) | 12 | 1-2 days |
| 11 (PDP-10 ⚪) | 3 | 0 (sign-off only) |
| 12 (verification) | 5 | 2-3 days |

**Total effort**: 14-21 working days for a single developer working
full-time. Scaling assumes the existing 34-test suite catches
regressions and the architecture stays intact.

**Risk areas**:
- Phase 6 (NPC AI) — dwarf-blocks-exit message can have subtle race
  conditions with the FORCED-room handling.
- Phase 7 (endgame) — repository setup mutates many objects atomically;
  ordering matters.
- Phase 12e (prose audit) — easy to miss capitalization variance.

---

## Dependency graph

```
Phase 1 (machinery)
   ├─ unblocks Phase 2 (conditional rows)
   └─ unblocks Phase 3 (probabilistic)

Phase 4 (vocab)
   └─ unblocks Phase 5 (prose), Phase 7 (endgame BLAST)

Phase 6 (NPC AI)
   └─ no hard dependencies, but improves Phase 12 verification clarity

Phase 7 (endgame)
   ├─ depends on Phase 4b (MIRROR object)
   ├─ depends on Phase 4a (BLAST verb)
   └─ feeds Phase 8 (scoring math)

Phase 9 (BACK + nav)
   └─ no hard dependencies

Phase 10 (flavor)
   └─ no hard dependencies, save for last

Phase 11 (PDP-10 ⚪)
   └─ user sign-off only

Phase 12 (verification)
   └─ depends on every preceding phase
```

---

## Acceptance criteria for "100% canon"

The port is canon-100% when **every** row of `CANON_FULL_AUDIT.md`
shows ✓ or ⚪ (with sign-off attached), and:

1. `tests/test_cca_canonical.gd` runs init → won via real commands and
   reaches 350/350 score (no hints accepted).
2. `tests/test_cca_conditional.gd` reports 62/62 covered.
3. `tests/test_cca_canon.gd` dashboard reports 100% on the architectural
   probes.
4. `tests/test_cca_topology.gd` reports 140/140 rooms aligned.
5. Every canon section-6 message either:
   - is verbatim emitted by the port at the canonical trigger, or
   - is documented as ⚪ scope-out with user sign-off.
6. The 5-letter parser truncation (canon msg #1: "I look at only the
   first five letters of each word") behaves byte-for-byte against
   canon test inputs.

---

## Next concrete step

Immediately tractable, minimal-risk, and unblocks Phase 2:

→ **Implement Phase 1a** (`here_or_carrying` gate type).

That alone closes 3 conditional rows (19:sw 211, 117:over 233, 122:sw 233).
After that, Phase 1b (`prop_not_n` with optional dest) closes 5 more.
Then Phase 2a (fissure-forward death) is a 30-line patch.

Each phase landing leaves the codebase in a shippable state (all
tests still green, audit coverage incrementally improves).
