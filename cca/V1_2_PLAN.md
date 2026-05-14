# CCA V1.2 — improvement plan

Companion to [`V1_REVIEW.md`](V1_REVIEW.md) (the canon-fidelity audit) and
[`ARCHITECTURE.md`](ARCHITECTURE.md) (the orchestrator + aspect-bus
model).

V1.0 closed at **1208 MATCHED / 7 LEFT-ONLY / 71 RIGHT-ONLY** canon
strings and **64/64 PASS** tests. V1.1 was the EM-review cleanup
(topology deduplication, `_SAVE_MAGIC`, pre-commit drift detector,
save-format versioning).

**V1.2 is the architectural pass.** Every piece of game state in the
driver that *could* live on an FSM moves to one. After V1.2, the
driver is unambiguously the GDScript/Godot adapter layer — UI, file
I/O, topology graph lookups, input parsing — with zero canon
game-state in it. The single 5,712-line `cca.fgd` becomes a tidy
multi-file Frame project.

The driving principle is unchanged from V1: **the FSMs are the canon
model**. Procedural latches and per-turn check functions in the
driver are vestiges of the early port. V1.2 finishes the move.

## Constraint — `@@[no_persist]` ships during V1.2

Frame RFC-0012's per-field `@@[no_persist]` annotation is expected
to land mid-V1.2 (target: 2026-05-13). **No phase blocks on it.**
Phases that would benefit from it are designed so the annotation is
additive — when it lands, we adopt it; until it lands, the
equivalent state lives in the driver as adapter-layer concerns.

Phases that adopt `@@[no_persist]` if/when available during V1.2:

- **Phase 0.2 (PromptDispatcher)** — currently designed as a
  non-persisted session FSM. With `@@[no_persist]` available, an
  alternative design (persist the FSM, mark transient fields)
  becomes possible but isn't preferred: modal interaction state
  *shouldn't* survive a restore. The current design stands.
- **Phase 0.13 (new — UI change-detection move)** — `_last_room`,
  `_last_endgame_state` move from driver onto Adventure with
  `@@[no_persist]`. Phase becomes a no-op if the annotation hasn't
  shipped by sign-off; tracked in Tier 4 in that case.

The plan does not assume the feature is absent. It assumes the
feature is *optional in V1.2* — the architecture is the same either
way.

## Constraint — Frame cross-file imports (Phase 0.0 deferred)

Inspection of the framec project (2026-05-12) confirms what
[`cca/frame/cca.fgd`](frame/cca.fgd)'s own header comment states:
*"Frame doesn't have an import mechanism, so a single `.fgd` must
contain every system that composes with another."* RFC-0014 added
`@@[main]` for multi-system `.fgd` files (one file → many systems
with one designated primary), but cross-file imports (`adventure.fgd`
referencing `@@Lamp` defined in `world.fgd`) are not yet specified.

`AspectBus` is currently duplicated between `aspects.fgd` and
`cca.fgd` for exactly this reason.

**Phase 0.0 (the logical file split) is deferred to V1.3** —
contingent on framec gaining cross-file imports. The CCA project
is a natural forcing function for that feature: a 7,500-line
single-file project is the canonical "you need imports now" case.

All 13 conversion phases below run against the existing single
`cca.fgd`. Each new `@@system` (PromptDispatcher in 0.2, Oyster in
0.11) lands in `cca.fgd` adjacent to its peers. The file ends V1.2
larger than it started, which is fine — the conversion *value*
isn't the file split; it's getting canon game-state off the driver
and onto FSMs.

---

## Tier 0 — Frame conversion (the substantive work)

13 phases plus a one-time file split. Each phase ends with green
tests, parse-clean pre-commit, and the drift detector at zero
unexpected items. Magic bumps batch into Phase 0.13 — one rev of
`_SAVE_MAGIC` covers all domain changes.

### Phase 0.0 — Logical file split (DEFERRED to V1.3)

**Status: deferred.** Requires framec to ship cross-file imports
first — see [the constraint section](#constraint--frame-cross-file-imports-phase-00-deferred)
above. The phase description below documents the intended end-state.

**What.** Split `cca.fgd` (5,712 lines) into six topical files plus
the existing `aspects.fgd`. New systems added in later phases land
directly in their target file.

```
cca/frame/
├── aspects.fgd      AspectBus + aspect stubs (existing, unchanged)
├── world.fgd        Lamp, Player, DarknessGate, BackpackLimit,
│                    MagicWordTeleport, ScoreLedger, Endgame
├── npcs.fgd         Bird, Snake, Bear, Troll, Dwarf, Pirate, Dragon
├── puzzles.fgd      CrystalBridge, Grate, RustyDoor, VendingMachine,
│                    Bottle, Plant, EggsIncantation, Oyster (new in 0.11)
├── items.fgd        Treasure, Item
├── interaction.fgd  Hint, PromptDispatcher (new in 0.2)
└── adventure.fgd    Adventure orchestrator
```

**How.** Mechanical move — copy each `@@system` declaration plus its
header comments into the target file. `build.sh` iterates the new
file list. The arcade-side mirror step picks up the new generated
files identically.

```bash
# build.sh — new file iteration list
for name in aspects world npcs puzzles items interaction adventure; do
    ...
done
```

**Persist posture.** No domain changes. **Save-format compatibility
must be verified post-split** — if framec's generated class layout
changes based on source file membership (field ordering, class load
order), the wire format breaks and we bump magic. The expected
answer is "the generated code is identical to the single-file
version," but verify with a save round-trip test before assuming.

**Verification.**

1. Run `./run_tests.sh` — all 64 tests pass.
2. Save → restore round-trip on a CCA1 save written with the
   pre-split build — confirm it still loads. If it doesn't, file
   layout has changed the wire format; bump magic and document why.
3. `check_cca_drift.py` reports zero unexpected items.

**Risk.** Low *if* framec supports multi-file composition. High if
it doesn't — but that's a framec fix, not a CCA workaround.

---

### Phase 0.1 — Canon scalars onto Adventure

**What.** Six driver-side `var` declarations that are pure
canon-derived world state move onto `@@system Adventure`'s domain:

| Driver field | Canon name | Source | Used by |
|---|---|---|---|
| `_old_loc` | `OLDLOC` | advent.for STMT 20-25 | `BACK` / `RETREAT` (msg #91 / #140) |
| `_old_loc2` | `OLDLC2` | advent.for STMT 20-25 | `BACK` when `OLDLOC == LOC` |
| `_brief_mode` | `ABBNUM` (flattened) | advent.for STMT 8260 | `BRIEF` revisit-display gate |
| `_look_detail_count` | `DETAIL` | advent.for STMT 30 | `LOOK` repeat cool-down (msg #15) |
| `_iwest_count` | `IWEST` | advent.for line 901 | Witts-hint west-counter (msg #181) |

Plus the related sibling that *was* a literal canon scalar but the
port simplified into a different shape:

| Driver field | Canon analog | Moves to (Phase 0.5) |
|---|---|---|
| `_dark_warned_room` | `WZDARK` (different shape) | DarknessGate (Phase 0.5, not here) |

**How.** Add five fields to Adventure's `domain:` block in
`adventure.fgd`. Add flat getter + setter pairs on the interface
(`old_loc(): int`, `set_old_loc(loc: int)`, etc.) — preserving the
current control flow exactly. Driver reads/writes become FSM calls.

**Persist posture.** All five **persist**. They are world state by
canon definition; restoring without them breaks `BACK`, `BRIEF`
cadence, and the witts-hint trigger.

**Verification.** Existing tests
(`test_cca_back_msg91_140.gd`, `test_cca_brief.gd`,
`test_cca_look_detail.gd`, `test_cca_witts_end.gd`,
`test_cca_dark_room_pit.gd`) pass unchanged. Extend
`test_cca_dwarf_persist.gd`'s round-trip pattern to verify all five
survive save/restore.

**Risk.** Low. Mechanical move; getters/setters preserve the
existing flow.

---

### Phase 0.2 — PromptDispatcher FSM

**What.** Five driver booleans implement a hand-rolled mini-FSM
("which Y/N prompt are we waiting on, if any?"). Reading
[driver.gd:518-614](godot/scripts/driver.gd#L518-L614) shows the
same shape repeated five times: check the latch, branch on YES/NO,
clear it, dispatch the side effect.

| Latch | Trigger verb | YES action | NO action |
|---|---|---|---|
| `_quit_pending` | `QUIT` (msg #22) | exit + msg #54 | continue + msg #54 |
| `_suspend_pending` | `SUSPEND` (msg #200) | save + exit | cancel + msg #54 |
| `_oyster_prompt_active` | First OYSTER reveal | spend 10pts + msg #194 | msg #14 |
| `_awaiting_revive` | Player death (msg #81/#83/#85) | reincarnate | end game (msg #82/#84/#86) |
| `_hint_pending != ""` | Per-turn hint trigger | spend cost + emit payload | dismiss |

**How.** New `@@system PromptDispatcher` in `interaction.fgd`:

```frame
@@system PromptDispatcher : RefCounted {
    interface:
        offer_quit()                 // -> $AwaitingQuitConfirm
        offer_suspend()              // -> $AwaitingSuspendConfirm
        offer_oyster()               // -> $AwaitingOyster
        offer_revive(deaths: int)    // -> $AwaitingRevive
        offer_hint(name: String)     // -> $AwaitingHint
        confirm()                    // YES path — emits event matching current state
        decline()                    // NO path
        cancel()                     // ESC or unrelated input
        is_active(): bool
        current(): String
    machine:
        $Idle { ... }
        $AwaitingQuitConfirm { ... }
        $AwaitingSuspendConfirm { ... }
        $AwaitingOyster { ... }
        $AwaitingRevive { ... }
        $AwaitingHint { ... }
}
```

Each substate handles `confirm` / `decline` explicitly, encoding
the per-prompt YES/NO branch as state-action code instead of as
five copies of an `if/elif` ladder in `_process_input`.

**Persist posture.** PromptDispatcher does **not** carry
`@@[persist]` decorators. It's a session-scoped FSM — modal
interactions don't survive a save/restore boundary cleanly. After
restore, prompts are clean; the driver re-issues a prompt if one
is genuinely owed (e.g. post-restore detects `player.is_dead()`
and calls `prompts.offer_revive()`).

This is a deliberate departure from "every `@@system` composed on
Adventure is persisted." It's load-bearing for a reason: persisting
the dispatcher would let a save land mid-prompt with no driver
context to feed it.

**Verification.** Existing modal tests
(`test_cca_quit_prompt.gd`, `test_cca_suspend.gd`,
`test_cca_oyster.gd`, `test_cca_resurrection.gd`,
`test_cca_hint_*.gd`) pass. Driver's `_process_input` shrinks
substantially: five `if _xxx_pending:` branches collapse into a
single dispatch through PromptDispatcher.

**Risk.** Medium. The five latches have subtle YES/NO asymmetries
(suspend NO continues; revive NO ends game; quit NO continues). The
FSM makes the differences visible per-state rather than scattered
across the driver.

---

### Phase 0.3 — Endgame substates ($Closing / $T25 / $T15 / $T5)

**What.** The cave-closing crescendo (canon advent.for STMT
10000-10100) currently lives as three driver-side one-shot booleans
(`_closing_warned_25`, `_closing_warned_15`, `_closing_warned_5`)
plus prose ladders in `_check_endgame_phase_change`. The shape is
a hierarchical state machine; the port spells it procedurally.

**How.** Extend Endgame's state hierarchy in `world.fgd`:

```
$Playing
$Closing
    $T25     // 25 turns to closure — msg #129
    $T15     // 15 turns — msg #130
    $T5      // 5 turns — msg #131-#133 ladder
$Closed      // wrenched-to-repository transition fires once
$InRepository
    (existing — DETONATE outcomes)
```

Each substate emits its own canon msg on entry; `tick()` advances
based on turn count. The three driver one-shot booleans go away.

**Persist posture.** State is FSM bookkeeping (always-included).
Turn counter inside each substate persists. Bump triggered (new
states reachable mid-save) — batched to 0.13.

**Verification.** Existing `test_cca_endgame.gd` passes; add a
deterministic-time test that walks the crescendo turn-by-turn and
asserts each substate's canon msg fires at the correct tick.

**Risk.** Low-medium. The HSM substructure removes the driver-side
prose-selection ladder; diff to `_run_per_turn_checks` shrinks.

---

### Phase 0.4 — Hint.\_offered + \_chest\_hint\_done

**What.** Driver carries `_hint_prompted: Dictionary = {}` —
"hint-name → has-been-auto-offered-this-session" — plus
`_chest_hint_done: bool` for the chest-only-outstanding hint
(canon msg #186). Both are per-Hint state living on the wrong
object.

**How.** Add to `@@system Hint` in `interaction.fgd`:

```frame
interface:
    mark_offered()
    has_been_offered(): bool
domain:
    _offered: bool = false       // persisted — survives saves
```

Driver's `_hint_prompted[name] = true` becomes
`hint.mark_offered()`. The chest-hint instance carries its own
`_offered`; `_chest_hint_done` deletes from the driver.

**Persist posture.** `_offered` **persists** — and that's *more*
canon-correct than the current session-only tracking. Adding the
field bumps magic; batched to 0.13.

**Verification.** Existing `test_cca_hint_*.gd` pass. Add
`test_cca_hint_offered_persist.gd`: offer hint → decline → save →
restore → re-enter trigger room → assert hint is not re-offered.

**Risk.** Low. Change is local to one parameterized FSM; driver
delta is two lines per call site.

---

### Phase 0.5 — `_dark_warned_room` onto DarknessGate

**What.** `_dark_warned_room: int = -1` tracks "have we already
fired msg #16 for the player's current dark room?" — gate-state on
darkness. Belongs on the FSM whose job is gating dark-room
behavior.

**How.** Add to `@@system DarknessGate` in `world.fgd`:

```frame
interface:
    mark_warned(room: int)
    has_warned(room: int): bool
    clear_warning()
domain:
    _warned_room: int = -1
```

Driver's `_check_dark_pit_hazard` (line 1771) becomes a thin
delegate: ask the FSM whether to emit msg #16, the pit-fall roll,
or nothing.

**Persist posture.** `_warned_room` **persists** — a save written
between the warning and the pit-fall roll must restore into the
"already warned" state so the next move triggers the roll, not
another warning. Magic bump batched to 0.13.

**Verification.** `test_cca_dark_room_pit.gd` passes unchanged.
Add a persistence test: warn, save, restore, move → assert
pit-fall roll fires (not a second warning).

**Risk.** Low.

---

### Phase 0.6 — Lamp warnings into Lamp state actions

**What.** `_check_lamp_warnings` (line 1848) checks Lamp's battery
threshold and emits canon msg #187 ("Your lamp is getting dim...")
or msg #189 ("Your lamp has run out of power.") at the right
ticks. The Lamp FSM already has `$Lit / $LowBattery / $Out` states
— the messages belong as state-entry actions.

**How.** Move msg emission into Lamp state actions in `world.fgd`.
Lamp exposes a single `get_warning(): String` query the driver
reads after `tick()`. Driver shrinks; canon prose lives next to
the state that fires it.

**Persist posture.** No new fields — Lamp's existing state +
battery_left already cover this. No magic bump.

**Verification.** `test_cca_lamp_warnings.gd` passes unchanged.

**Risk.** Low.

---

### Phase 0.7 — Hint eligibility into each Hint's $Available

**What.** `_check_hint_prompts` (line 849) iterates the six hints,
evaluating per-hint trigger predicates (player in bird room,
player at cave entrance, etc.) inline in the driver. Each Hint
should own its own eligibility predicate via state.

**How.** Hint's `$Available` state owns the predicate. Driver
calls `hint.tick(player_room, snapshot_of_world)` once per turn;
Hint transitions to `$Offered` when the predicate matches and the
threshold counter rolls over. PromptDispatcher.offer_hint(name) is
called by the driver when any hint reports it just transitioned.

The trigger predicates themselves involve cross-system queries
(player room, lamp state, treasures-carried count), so the driver
passes a small snapshot record. Frame doesn't have records as a
first-class type — the snapshot is a multi-arg `tick(room: int,
has_lamp: bool, ...)` call.

**Persist posture.** Threshold counter already persists. No new
fields.

**Verification.** Existing `test_cca_hint_*.gd` tests pass.

**Risk.** Low-medium. The predicates are simple; risk is just
making sure the driver-side snapshot has every field a predicate
needs.

---

### Phase 0.8 — Resurrection cycle onto Player

**What.** `_check_player_death` (line 1981) tracks death count
via `fsm.player.get_deaths()` and emits the msg #81 / #83 / #85
ladder for the first three deaths plus msg #86 for permadeath.
Player already counts deaths; the prompt prose belongs on Player
too. The driver-side `_awaiting_revive` latch moves to
PromptDispatcher's `$AwaitingRevive` (Phase 0.2).

**How.** Add to `@@system Player` in `world.fgd`:

```frame
interface:
    get_revive_prompt(): String   // returns canon msg #81/#83/#85 by death count
    get_permadeath_msg(): String  // returns canon msg #86
```

Driver's death handler becomes: detect `player_state == "dead"`,
ask Player for the prompt prose, hand off to
`prompts.offer_revive(deaths)`.

**Persist posture.** No new persisted state — death count already
on Player.

**Verification.** `test_cca_resurrection.gd` passes unchanged.

**Risk.** Low.

---

### Phase 0.9 — Dwarf destination picking onto Dwarf / Adventure

**What.** `_pick_dwarf_destination` (line 813) implements the
canon BITSET / FORCED / no-backtrack / no-surface filter for
dwarf movement. The driver does it because it owns the topology
graph (`room_exits`). `_dwarf_first_encounter_done` (a one-shot
flag for the msg #3 narration) and `_dwarf_walk_rng` (a shared
RandomNumberGenerator) also live on the driver.

**How.** Two clean moves:

1. `_dwarf_first_encounter_done` → Adventure domain (one-shot is
   per-game, not per-dwarf). Or a new state `$FirstDwarfSeen` on
   Adventure's own machine.
2. `_dwarf_walk_rng` → **delete from driver.** Each `@@system
   Dwarf(seed: int)` already takes a seed; the per-dwarf RNG
   state should live inside the FSM, deterministic from the seed
   and the FSM's tick history. The "shared RNG" was a port
   shortcut; per-dwarf RNG is more canon-faithful (each dwarf is
   parameterized).

The destination-picking itself stays in the driver — it needs the
topology graph, which is legitimately a driver concern. But the
*filter logic* (BITSET / FORCED / no-backtrack) moves to a Dwarf
operation that takes a candidate list and returns the pick:

```frame
@@system Dwarf {
    operations:
        pick_destination(candidates: list, player_room: int, low_loc: bool): int
}
```

Driver supplies candidates from `room_exits`; Dwarf applies canon
filters and picks. Cleanly separates topology (driver) from
canon-filter behavior (FSM).

**Persist posture.** Dwarf's RNG state needs to persist for
deterministic save/restore. Adding RNG state to Dwarf domain →
magic bump batched to 0.13.

**Verification.** `test_cca_dwarf_persist.gd` and
`test_cca_multi_dwarf.gd` pass. Determinism test: pin seeds, run
N turns, snapshot dwarf positions; reset, run again, assert
identical positions.

**Risk.** Medium. RNG-as-FSM-state needs care — verify framec's
persist serialization handles whatever RandomNumberGenerator-like
type Dwarf carries.

---

### Phase 0.10 — Pirate stash/rustle onto Pirate

**What.** `_check_pirate_steal` (line 1816) and
`_check_pirate_rustle` (line 1838) plus `_pirate_already_stole:
bool = false` all live on the driver. The Pirate FSM exists and
holds the position; the steal-threshold check and the
once-per-game `_pirate_already_stole` belong on Pirate.

**How.** Add to `@@system Pirate`:

```frame
interface:
    try_steal(treasures_carried: int): bool   // returns true if pirate stole this turn
    has_already_stolen(): bool
    rustle_msg(): String                       // canon msg #127 "rustling..."
```

Driver's two `_check_pirate_*` functions collapse into one call:
`if pirate.try_steal(treasures): emit msg #128 / #129`. The
`_pirate_already_stole` flag moves into Pirate as a persisted
domain field.

**Persist posture.** New persisted field → magic bump batched.

**Verification.** Existing pirate tests pass.

**Risk.** Low.

---

### Phase 0.11 — Oyster FSM (new)

**What.** The clam-pearl interaction is the *only* puzzle without
its own FSM. Currently:
- `_oyster_revealed: bool` on driver (line 266) — has the player
  opened the oyster?
- `_oyster_prompt_active: bool` on driver (line 265) — moves to
  PromptDispatcher in Phase 0.2
- Clam/oyster reveal logic dispatched ad-hoc against the Item FSM
  for the clam-pair

A small purpose-built `Oyster` FSM is the right home.

**How.** Add `@@system Oyster` in `puzzles.fgd`:

```frame
@@system Oyster : RefCounted {
    interface:
        open()                       // attempt OPEN/CRACK on clam
        reveal_pearl()               // first OPEN succeeds → pearl spawns
        is_open(): bool
        has_been_revealed(): bool
    machine:
        $Clam {
            open() -> $Oyster { ... }     // canon msg #124
        }
        $Oyster {
            open() -> $Open { ... }       // already open, msg #14 or hint
        }
        $Open { ... }
}
```

Driver delegates clam/oyster verbs to the FSM; the prompt path
goes through PromptDispatcher.

**Persist posture.** New `@@system`, new state. Magic bump batched.

**Verification.** Existing oyster tests pass; add round-trip test.

**Risk.** Low-medium. Cross-FSM choreography with Treasure (the
pearl is a treasure) needs the same orchestrator-broker pattern
the bridge and grate use.

---

### Phase 0.12 — `_visited_rooms` onto ScoreLedger

**What.** `_visited_rooms: Dictionary = {}` on the driver counts
unique rooms visited; ScoreLedger computes `visit_score` by
reading it. The dictionary belongs on the ledger.

**How.** Move into `@@system ScoreLedger` in `world.fgd`. Driver
calls `score_ledger.mark_visited(room)` after every move.
`visit_score()` reads from the FSM's own state.

**Persist posture.** Persisted (it's already persisted indirectly
via `_visited_rooms`'s round-trip, but currently lives on the
wrong object). Magic bump batched.

**Verification.** Score-related tests pass; add persistence test
for the visited set.

**Risk.** Low.

---

### Phase 0.13 — UI change-detection helpers onto Adventure (conditional)

**Conditional on `@@[no_persist]` shipping during V1.2.** If the
annotation isn't available by sign-off, this phase moves to Tier 4
unchanged.

**What.** Two driver fields are pure change-detection helpers used
for "did the room change since last turn?" / "did endgame state
change since last turn?" rendering decisions:

- `_last_room: int = -1`
- `_last_endgame_state: String = "active"`

They're UI ergonomics — recomputable from the FSM on the first
read after restore. They live in the driver today because that
was the only option without `@@[no_persist]`.

**How.** Add to `@@system Adventure` in `adventure.fgd`:

```frame
domain:
    @@[no_persist]
    _last_room_seen: int = -1
    @@[no_persist]
    _last_endgame_seen: String = ""
```

Plus getter / setter pairs. On restore, both fields snap to their
declared defaults (per RFC-0012 contract). The driver re-seeds
them on the first post-restore tick, which is what it would do
anyway.

**Persist posture.** `@@[no_persist]` on both — they're transient
by definition. No magic bump (the annotation excludes them from
the wire format).

**Verification.** No new tests required — these are pure
change-detection. Existing per-turn-tick tests cover the visible
behavior.

**Risk.** Low. The fallback (leave in driver) is exactly the
current behavior; adopting the FSM placement is purely additive.

---

### Phase 0.14 — `_SAVE_MAGIC` bump to `CCA2`

**What.** All preceding phases that add domain fields or states
batch into a single magic bump. Per `SAVE_FORMAT.md`'s contract.

**How.** Per the documented procedure:

1. In both
   [`cca/godot/scripts/driver.gd`](godot/scripts/driver.gd) and
   [`arcade/godot/scripts/cca_main.gd`](../arcade/godot/scripts/cca_main.gd),
   change:
   ```gdscript
   static var _SAVE_MAGIC: PackedByteArray = PackedByteArray([67, 67, 65, 50])  # "CCA2"
   ```
2. Add to the version log in
   [`SAVE_FORMAT.md`](SAVE_FORMAT.md):
   > `CCA2` | 2026-05-12 | V1.2 architectural pass: canon scalars
   > on Adventure, Endgame $Closing/$T25/$T15/$T5 substates,
   > Hint.\_offered, DarknessGate.\_warned\_room, Pirate.\_already\_stolen,
   > Dwarf RNG persistence, ScoreLedger.\_visited, new Oyster FSM,
   > new PromptDispatcher FSM (session-scoped, not persisted).
3. Commit. In-flight V1 saves reset gracefully with the friendly
   "starting fresh" message.

**Risk.** None — that's what the format was versioned for in V1.1.

---

## Tier 1 — Real bugs (½ day)

### Canonize `_format_inventory` drift

`check_cca_drift.py`'s EXPECTED_DIVERGENCES table flags
`_format_inventory` as "small phrasing drift on a couple of item
labels; flagged for canonization in V1.2." Both implementations
should produce byte-identical output for the same item set. Pick
the version that matches canon §5 `advent.dat` prop strings,
propagate to both files, remove the entry from
EXPECTED_DIVERGENCES.

### Arcade-specific test coverage

The arcade chapter has zero arcade-specific tests today. The
drift detector catches structural regressions; it doesn't catch
behavioral ones (ExitDialog flow, return-to-menu integration,
Cabinet F-key handling). Add a minimal smoke test that:

- Boots the arcade chapter under `--headless` against a known save.
- Exercises Esc → ExitDialog → Save+Exit path.
- Verifies the save file is well-formed.

The bar: *one* arcade-side test that would have caught the May 10
"Nonexistent function `mark_loaded_from_save`" crash.

---

## Tier 2 — Doc archival (1 hr)

V1's canon-fidelity push generated three large planning docs that
are historical record post-V1:

- [`CANON_FULL_AUDIT.md`](CANON_FULL_AUDIT.md) — V1 gap inventory
- [`CANON_FULL_PLAN.md`](CANON_FULL_PLAN.md) — V1 implementation roadmap
- [`CANON_DELTAS.md`](CANON_DELTAS.md) — pre-V1 divergence log

`TODO.md` still points at them as "the authoritative canon-fidelity
gap inventory." Move them to `cca/docs/historical/`, update
`TODO.md` to point at `V1_REVIEW.md`, leave a one-line forwarding
breadcrumb in each archived doc.

Current top-level docs that stay:
`ARCHITECTURE.md`, `EVALUATION.md`, `MODEL_CHECKING.md`,
`CANON_LOCATIONS.md`, `SAVE_FORMAT.md`, `V1_REVIEW.md`,
`V1_2_PLAN.md` (this doc), `TODO.md`, `README.md`.

---

## Tier 3 — CI hardening (20 min)

The pre-commit hook
([`cca/scripts/pre-commit`](scripts/pre-commit)) runs parse-check
+ drift detection on commit. CI should run the same checks plus
the test suite. Add a GitHub Actions workflow:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: chickensoft-games/setup-godot@v2
        with: { version: "4.6.2" }
      - name: Run drift detector
        run: python3 cca/scripts/check_cca_drift.py
      - name: Run canon audit (regression guard)
        run: python3 cca/canon/audit_string_join.py --max-left-only 7
      - name: Run test suite
        run: cd cca && ./run_tests.sh
      - name: Arcade smoke test
        run: cd arcade && ./run_smoke_test.sh
```

The `--max-left-only 7` flag is a regression guard — the current
audit floor. A canon-string regression bumps the count and fails
CI.

---

## Tier 4 — Deferred (capture, don't do)

Items that surfaced during V1.2 planning but aren't V1.2's job:

- **F5 / F9 quick-save / quick-load** — would touch Frame source
  on the CCA side; deferred per the earlier arcade-keys plan's
  "out of scope" note.
- **`@@[no_persist]` adoption when shipped** — move UI change-
  detection helpers (`_last_room`, `_last_endgame_state`) and any
  RNG-handle fields onto FSMs with `@@[no_persist]`. Until then,
  these stay in the driver as adapter-layer state.
- **`@@[persist_fields([...])]` adoption when shipped (RFC-0016)** —
  replace many per-field `@@[no_persist]` annotations with one
  inclusion-list declaration per system. Refactor, not rewrite.
- **Inform 6 transpile path** — port-emit Frame → Inform 6 so the
  canon model runs under the Z-machine. Speculative.
- **Multi-dwarf save bundling** — five separate dwarf blobs in
  the save could be one batched serialization. Profile first.

---

## Sequencing

Phases share no code paths beyond the magic bump at 0.13.
Recommended order:

| Phase | Effort | Risk | Notes |
|---|---|---|---|
| 0.0 — File split | ½ day | Low (framec willing) | precondition for everything else |
| 0.1 — Canon scalars | ½ day | Low | |
| 0.2 — PromptDispatcher | 1 day | Medium | the big one |
| 0.3 — Endgame substates | ½ day | Low-medium | |
| 0.4 — Hint.\_offered | ½ day | Low | |
| 0.5 — DarknessGate.\_warned\_room | ¼ day | Low | |
| 0.6 — Lamp warnings | ¼ day | Low | |
| 0.7 — Hint eligibility | ½ day | Low-medium | |
| 0.8 — Resurrection cycle | ¼ day | Low | |
| 0.9 — Dwarf picking + RNG | ¾ day | Medium | RNG-as-FSM-state |
| 0.10 — Pirate stash | ¼ day | Low | |
| 0.11 — Oyster FSM | ½ day | Low-medium | |
| 0.12 — \_visited\_rooms | ¼ day | Low | |
| 0.13 — UI change-detection (conditional) | ¼ day | Low | only if `@@[no_persist]` ships during V1.2 |
| 0.14 — `_SAVE_MAGIC` bump | 10 min | None | batches 0.1–0.12 |
| 1 — Format inventory + arcade tests | ½ day | Low | |
| 2 — Doc archival | 1 hr | None | |
| 3 — CI workflow | 20 min | None | |

Total: ~6.5 days of focused work for the full V1.2 surface. Each
Tier 0 phase can ship as a separate PR — the drift detector +
version log keep them independently shippable.

## Sign-off criteria for V1.2

- All Tier 0 phases land with green tests.
- `check_cca_drift.py` reports zero unexpected items.
- `audit_string_join.py` reports ≤7 LEFT-ONLY (V1 floor).
- `_format_inventory` removed from EXPECTED_DIVERGENCES.
- Arcade smoke test in place and passing.
- `_SAVE_MAGIC` is `CCA2` with version log updated.
- Driver line count drops from 2,419 to ~1,500-1,700 with no
  canon game-state left in any `var _*` declaration outside the
  adapter-layer inventory below.
- This document moves to `cca/docs/historical/V1_2_PLAN.md` once
  V1.2 ships.

## Driver inventory after V1.2 — what stays

The adapter-layer concerns that legitimately remain in the driver:

- Godot lifecycle (`_ready`, `_input`, `_notification`)
- UI rendering — RichTextLabel output, BBCode color codes,
  prompt formatting, ASCII art
- LineEdit input plumbing + `_input_history` recall
- File I/O — `_save_game` / `_load_game` byte-array round-tripping
- Topology dispatch — `_handle_movement`, `_walk_to_dest`
  (graph traversal over `room_exits` / `gated_exits`)
- Verb parser — `_parse`, `_truncate5`, synonym table
- Intercept routing — the `_intercept_*` methods (canonical
  bus-aspect callers)
- Per-turn orchestration — `_run_per_turn_checks` calls FSM ticks
  in defined sequence
- Output formatters — `_format_inventory`, `_print_welcome`,
  `_print_help`, `_print_info`, `_print_crowther_map`
- UI change-detection helpers — `_last_room`,
  `_last_endgame_state` (move to FSMs with `@@[no_persist]` when
  that ships)
