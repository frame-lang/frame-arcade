# Canonical Journey — full player walkthrough

This document specifies the **complete canonical CCA happy path** as a
player would actually type it through the Driver. The Frame state machine
in [`cca/frame/canonical_journey.fgd`](frame/canonical_journey.fgd) encodes
it; the test harness in [`cca/tests/test_cca_canonical_journey.gd`](tests/test_cca_canonical_journey.gd)
walks it via the real `Driver._process_input`.

## Why this exists

The existing 64 CCA tests follow one of two shapes that both bypass the
player UX:

1. `adv.do_command(...)` to drive the FSM directly, then assert FSM state.
   Skips the parser, room descriptions, and Y/N prompts.
2. `adv.player.move_to(N)` to teleport to a specific room before
   exercising one mechanic. Skips navigation, lamp drain, dwarf walks,
   pirate steals, encounter triggers.

The canonical journey test is the only one that walks through the
*Driver* — parser, FSM dispatch, per-turn tick, log buffer. It catches
player-visible bugs the other tests can't see (e.g. an item missing
from a room description, or a Y/N prompt firing too early). Two such
bugs surfaced when the test was first run; both are now fixed and locked
in by Stage 1 assertions.

## Methodology

Each milestone is a state in `CanonicalJourney` (Frame source). The
state declares:

- `commands_from_previous(): Array` — typed commands to reach this state
- `expected_room(): int` — `Adventure.player_room()` after commands fire
- `expected_in_log(): Array` — substrings that MUST appear in the log delta
- `expected_not_in_log(): Array` — substrings that MUST NOT appear

The harness loops: snapshot log length, send commands, diff log, assert.

Canon teleports (XYZZY, PLUGH, PLOVER) are used where canonical — they
ARE legitimate player actions and exercise the MagicWordTeleport aspect.
Topology shortcuts (`building`, `outdoors`, `surface`) are used for the
canonical deposit-walks back to the well-house, mirroring real-player
behavior.

## Stages

```
Stage 1  Cave Entry           states  1-4    ~15 cmds   ~5s  ✓ shipped
Stage 2  Descent + first room states  5-9    ~25 cmds  ~10s
Stage 3  Magic Words & NPCs   states 10-15   ~40 cmds  ~15s
Stage 4  Hard Treasures       states 16-19   ~35 cmds  ~15s
Stage 5  Endgame              states 20-23   ~20 cmds  ~10s
```

Total: ~135 commands, ~55s. All canonical, all through the real Driver.

---

## Stage 1: Cave Entry (shipped)

### 1. `$AtRoad`

- **Commands**: (none — start state)
- **Expected room**: 1 (end of road)
- **In log**: `END OF A ROAD`
- **Not in log**: (none)

### 2. `$WellHouseGather`

- **Commands**: `e`
- **Expected room**: 3 (well house)
- **In log**: `WELL HOUSE`, `keys`, `lamp`, `bottle`, `food`
- **Not in log**: `trying to get into the cave` (premature hint)

### 3. `$WellHouseStocked`

- **Commands**: `take keys`, `take lamp`, `take food`, `take bottle`
- **Expected room**: 3
- **In log**: (no specific — multiple `OK` acceptable)
- **Not in log**: `I don't know how to apply` (lamp not parseable),
  `trying to get into the cave` (premature hint)

### 4. `$Done` (Stage 1 only)

Terminal for the shipped stage. Stage 2 replaces with `$BackToRoad`.

---

## Stage 2: Descent + Cobble Crawl

### 5. `$BackToRoad`

- **Commands**: `w`
- **Expected room**: 1
- **In log**: `END OF A ROAD`

### 6. `$AtDepression`

- **Commands**: `s`, `s`, `s` (room 1 → 4 valley → 7 slit → 8 depression)
- **Expected room**: 8 (depression / outside grate)
- **In log**: `depression`, `grate`

### 7. `$BelowGrate`

- **Commands**: `unlock grate`, `down`
- **Expected room**: 9 (below grate, dark)
- **In log**: `pitch dark` (canon msg #16)
- **Not in log**: `pit` death (player hasn't tried to move yet)

### 8. `$LampLit`

- **Commands**: `light lamp`
- **Expected room**: 9
- **In log**: `Your lamp is now on` (or canon equivalent)
- **Not in log**: `pitch dark`

### 9. `$CobbleCrawl`

- **Commands**: `w`
- **Expected room**: 10 (cobble crawl)
- **In log**: `crawl`, `cage`

---

## Stage 3: Magic Words + Bird/Snake/Dragon

### 10. `$DebrisRoom`

- **Commands**: `take cage`, `w` (10 → 11 debris)
- **Expected room**: 11
- **In log**: `rod`, `debris`

### 11. `$RodAndXyzzy`

- **Commands**: `take rod`
- **Expected room**: 11
- **In log**: `OK`

Canon side-note: at room 11 the player canonically reads `XYZZY`
inscribed on the wall, learning the magic word.

### 12. `$BirdChamber`

- **Commands**: navigate to room 13 (bird chamber) — `w` from 11 → 14
  (which is the Pit Hall in canon, leading down to 15+). Actual path:
  `w` (11 → 14), then check room — TODO verify exact route. Canon: from
  debris room, west takes you to a small chamber with a bird and a
  brass-bound book; that's canon room 13 in our topology.
- **Expected room**: 13
- **In log**: `bird`, `chamber`

### 13. `$BirdCaptured`

- **Commands**: `take bird`
- **Expected room**: 13
- **In log**: `OK`
- **Note**: bird-take requires the cage; assertion validates that.

### 14. `$SnakeRoom`

- **Commands**: navigate to room 19 (Hall of Mt King / snake room). Canon
  path from bird chamber: `down` (13 → 14), `e` (14 → 15 Hall of Mists),
  `s` (15 → 19 Hall of Mt King). Three commands.
- **Expected room**: 19
- **In log**: `snake`, `barring the way`

### 15. `$SnakeGone`

- **Commands**: `release bird`
- **Expected room**: 19
- **In log**: `bird attacks`, `snake` (canon msg #30)
- **Not in log**: `devoured` (would mean caged-bird-drop wrong)

---

## Stage 4: Dragon, Troll, Bear, Treasures

### 16. `$DragonCanyon`

- **Commands**: navigate to room 119 (dragon canyon). Canon: from Hall of
  Mt King, the dragon's room is reached via specific passages. Practical:
  `move 119` (direct teleport via Adventure's move command, NOT canonical
  but used by test_cca_full.gd). For a true player walk: traverse via
  the canonical exits — TODO map specific commands.
- **Expected room**: 119
- **In log**: `dragon`, `Persian rug`

### 17. `$DragonDead`

- **Commands**: `attack dragon`, `yes` (canon: "With what? Your bare
  hands?" — answer Yes to confirm bare-handed attack)
- **Expected room**: 119
- **In log**: `Vanquished`, `dragon` (canon kill prose)
- **Not in log**: `bounces harmlessly` (would mean axe-throw branch fired)

### 18. `$RugAndTrollPay`

- **Commands**: `take rug`, navigate to troll bridge (room 117) — TODO
  exact path, `drop rug` (or `give rug troll`)
- **Expected room**: 117
- **In log**: `troll`, `vanish` (canon msg: troll accepts treasure)

### 19. `$BearFreed`

- **Commands**: navigate to bear chamber (room 130). Canon path involves
  crossing the now-clear troll bridge. Then `feed bear`, `take chain`.
- **Expected room**: 130
- **In log**: `bear`, `chain`
- **Not in log**: `mauled` (failed feed)

---

## Stage 5: Deposit-Loop, Endgame, Victory

The deposit-loop pattern: pick up treasure → return to well-house →
`drop X` → leave. Repeat for all 15 treasures. Canon: at the well-house
(room 3), dropped treasures count toward the deposit score; once all 15
are deposited the endgame closing-phase triggers.

This phase has many treasure round-trips. For the canonical journey
test we exercise ONE round-trip explicitly (gold, the easiest), then
fast-forward the remaining 14 via `_deposit` helper (acceptable
because each round-trip is structurally identical to gold's path).

### 20. `$GoldDeposited`

- **Commands**: navigate to room 18 (gold nugget chamber), `take gold`,
  return to well-house via topology shortcut `building` or canonical
  walk. `drop gold`.
- **Expected room**: 3
- **In log**: `gold`, `OK`

### 21. `$AllDeposited`

- **Commands**: (helper teleports + drops for the remaining 14 treasures;
  see [`test_cca_full.gd`](tests/test_cca_full.gd) batch_a/b/c)
- **Expected**: `treasures_deposited() == 15`
- **In log**: closing-phase canon msg #129 (sepulchral voice)

### 22. `$InRepository`

- **Commands**: drive endgame timer to zero via 30 `tick` calls
  (canonical: closing-phase counter expires, player wakes in main
  office, canon room 115)
- **Expected room**: 115
- **In log**: canon msg #132 (cave is now closed)

### 23. `$Victory`

- **Commands**: `detonate marker` (canonical endgame win path —
  Blast with rod2 at the marker)
- **Expected**: `endgame_won() == true`
- **In log**: `loud explosion`, `cheering band of friendly elves`,
  final score line

### 24. `$Done`

Terminal. Harness loop exits.

---

## Open TODOs in this draft

Marked with `TODO` above:

- Stage 3 step 12: exact path from debris room (11) to bird chamber (13)
- Stage 4 step 16: walking commands for room 19 → room 119
- Stage 4 step 18: walking commands from dragon canyon to troll bridge
- Stage 4 step 19: path through troll bridge to bear chamber (130)
- Stage 5 step 21: which 14 remaining treasures to fast-forward and how

These will resolve as the FSM is written — for each transition, I'll
check `topology.gd` for the canonical exits and pick the shortest path.
Where canonical magic words apply (XYZZY, PLUGH, PLOVER), they're used.

## Coverage gaps acknowledged

What this journey **doesn't** cover (deferred to focused tests):

- Multi-dwarf encounters (probabilistic; covered by `test_cca_multi_dwarf`)
- Pirate steal mechanics (probabilistic; covered by `test_cca_pirate`)
- Witt's End 95/5 bounce (probabilistic; covered by `test_cca_witts_end`)
- Hint Y/N prompt flows (covered by `test_cca_hints`)
- Save/restore round-trip (covered by `test_cca_save_restore` etc.)
- Lamp battery countdown to zero (covered by `test_cca_lamp`)
- Specific canon prose for ~60 minor objects (covered by `test_cca_scenery_flavor`,
  `test_cca_minor_verbs`, etc.)

The canonical journey is a **happy path**, not an exhaustive test
suite. The other 64 tests cover edge cases.
