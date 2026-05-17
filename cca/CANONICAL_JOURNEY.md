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

## Stages — all shipped, 32 states

```
Stage 1  Cave Entry           states  1-3    ✓ shipped
Stage 2  Descent + Cobble Crawl states 4-9   ✓ shipped
Stage 3  Bird/Snake           states 10-14   ✓ shipped
Stage 4  Dragon/Troll/Bear    states 15-21   ✓ shipped
Stage 5  Deposit-loop + endgame states 22-31 ✓ shipped (with shortcuts)
                              state  32      $Done (terminal)
```

Total: ~90 player commands + 2 harness shortcuts (treasure-fill,
endgame-tick), <5s runtime. 100+ assertions, 65/65 suite passes.

The two harness shortcuts ($TreasuresFilled and $InRepository)
fast-forward through paths whose mechanics are already covered
by stages 1-5a and by the 64 other tests: the remaining 12
treasure round-trips after gold, and the 35 ticks of closing-
phase clock advancement. Walking each of those canonically would
add ~150 commands without exposing new bugs.

---

## States — authoritative table

Each row is a `@@system CanonicalJourney` state in
[`cca/frame/canonical_journey.fgd`](frame/canonical_journey.fgd).
Commands are passed verbatim through `Driver._process_input` —
exactly what a real player would type.

| # | State | Commands from previous state | Expected room |
|---|---|---|---|
| 1 | `$AtRoad` | (none — priming) | 1 |
| 2 | `$WellHouseGather` | `e` | 3 |
| 3 | `$WellHouseStocked` | `take keys`, `take lamp`, `take food`, `take bottle` | 3 |
| 4 | `$BackToRoad` | `w` | 1 |
| 5 | `$AtDepression` | `s`, `s`, `s` | 8 |
| 6 | `$BelowGrate` | `unlock grate`, `down` | 9 |
| 7 | `$LampLit` | `light lamp` | 9 |
| 8 | `$CobbleCrawl` | `w` | 10 |
| 9 | `$DebrisRoom` | `take cage`, `w` | 11 |
| 10 | `$BirdChamber` | `w`, `w` | 13 |
| 11 | `$BirdCaptured` | `take bird` | 13 |
| 12 | `$SnakeRoom` | `w`, `down`, `n` | 19 |
| 13 | `$SnakeGone` | `release bird` | 19 |
| 14 | `$DragonCanyon` | `n`, `down`, `bedquilt`, `slab`, `up`, `s` | 119 |
| 15 | `$DragonDead` | `attack dragon`, `yes` | 119 |
| 16 | `$RugTaken` | `take rug` | 119 |
| 17 | `$TrollBridge` | `n`, `down`, `n`, `w`, `oriental`, `w`, `sw`, `up` | 117 |
| 18 | `$TrollPaid` | `throw rug` | 117 |
| 19 | `$BearChamber` | `over`, `ne`, `e`, `se`, `s`, `e` | 130 |
| 20 | `$BearFed` | `feed bear` | 130 |
| 21 | `$ChainTaken` | `take chain` | 130 |
| 22 | `$BearReleased` | `drop chain`, `take chain` | 130 |
| 23 | `$WalkBackToWellHouse` | `w`, `w`, `n`, `w`, `w`, `over`, `sw`, `down`, `se`, `se`, `ne`, `e`, `up`, `e`, `up`, `s`, `e`, `up`, `depression`, `building`, `e` | 3 |
| 24 | `$ChainDeposited` | `drop chain` | 3 |
| 25 | `$WalkToGold` | `w`, `depression`, `down`, `w`, `w`, `up`, `w`, `w`, `down`, `s` | 18 |
| 26 | `$GoldTaken` | `take gold` | 18 |
| 27 | `$WalkBackWithGold` | `out`, `n`, `n`, `n`, `plugh` | 3 |
| 28 | `$GoldDeposited` | `drop gold` | 3 |
| 29 | `$TreasuresFilled` | (harness shortcut: 13× `fsm.endgame.treasure_deposited()`) | 3 |
| 30 | `$EndgameClosing` | `look` | 3 |
| 31 | `$InRepository` | (harness shortcut: 35× `fsm.tick()`) | 116 |
| 32 | `$Victory` | `blast` | (any — game over) |

## Canonical mechanics validated by these states

- **Surface item gather** (states 2-3): canonical room 3 description
  must enumerate all four starter items (keys/lamp/bottle/food);
  no premature hint Y/N prompts.
- **Grate / dark / lamp lifecycle** (states 5-7): unlock grate
  with keys, descend safely, light lamp before walking in the
  dark to avoid the pit-fall hazard.
- **Cobble crawl → bird-chamber path without rod** (states 8-11):
  canonical sequence avoids taking the rod at room 11 because the
  rod-with-star scares the bird (canon msg #26). Rod stays for
  later use.
- **Bird+cage+snake mechanic** (states 12-13): bird in cage,
  walked to Hall of Mountain King (canon 19), `release bird`
  drives off the snake (canon msg #30).
- **Custom motion-alias commands** (states 14, 17, 19, 23):
  canonical CCA recognizes `bedquilt`, `slab`, `oriental`, `over`,
  `ne`, `sw`, `se`, `depression`, `building` as motion verbs the
  driver routes via the topology's exits dict. Surfaced a driver
  bug during construction (fixed in commit 3d68913).
- **Bare-handed dragon kill** (states 14-16): `attack dragon` + `yes`
  → canon msg #49 "Vanquished a dragon with your bare hands!"
- **Troll bridge appeasement** (states 17-18): `throw rug` (not
  drop) — canon: troll catches treasure thrown at him; drop just
  puts it on the ground.
- **Bear feeding + chain release** (states 19-22): feed bear with
  the well-house food, take the chain (bear becomes $Following),
  drop chain to detach the bear (avoid the bear-collapses-bridge
  death at canon msg #162), re-take the chain.
- **Gold-blocks-the-steps puzzle** (states 25-27): with gold in
  hand, `15:up` is gated; canonical workaround is to head NORTH
  through the Hall of Mountain King area up to Y2 (canon 33)
  and use the PLUGH magic word to teleport to the well-house.
- **Deposit at well-house** (states 24, 28): `drop X` at canon
  room 3 deposits the treasure into the score ledger.
- **Endgame closing-phase** (state 30): on the 15th deposit,
  canon msg #129 "A sepulchral voice reverberating through the
  cave, says, 'Cave closing soon...'" fires.
- **Repository BLAST victory** (state 32): canon msg #133 "There
  is a loud explosion... a cheering band of friendly elves carry
  the conquering adventurer off into the sunset."

## Harness shortcuts (transparent, documented)

Two states accept FSM-direct manipulation rather than walking
through 150+ canonical commands. The test harness
([`cca/tests/test_cca_canonical_journey.gd`](tests/test_cca_canonical_journey.gd))
documents the bypass:

- `$TreasuresFilled`: fills `treasures_deposited` up to canon 15
  via 13× `fsm.endgame.treasure_deposited()` calls. The 12 missed
  treasure round-trips after gold (silver/diamonds/jewelry/pearl/
  vase/eggs/trident/emerald/spices/chest/pyramid/coins) share
  the same mechanic as gold; their walks add ~150 commands
  without exposing new canon-fidelity bugs.
- `$InRepository`: drives the closing-phase clock with 35×
  `fsm.tick()` calls. Player would canonically type LOOK (or any
  command) repeatedly during the closing phase; the harness
  shortcut skips that boredom.

Both bypasses are gated by `state_name() == "..."` checks in
the harness loop — opt-in per-state, not hidden.

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
