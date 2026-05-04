# CCA-in-Frame: an honest evaluation

**Question:** Does Frame help build CCA, or is it the wrong tool
for adventure-game shape?

**TL;DR:** Frame is **a measured win** for CCA — bigger than I
estimated mid-session, smaller than the arcade chapters. Three
specific Frame features (composition + `@@[persist]`, multi-stage
HSMs, parameterized parallel instances) earn their keep cleanly.
Three other systems (Snake, Troll, Dragon) are small enough that
plain GDScript would have been roughly equivalent. The aspect-bus
pattern *layered over* Frame is where the architectural payoff
actually lands.

This document scores each system honestly so the chapter
prose, when it gets written, can pitch Frame correctly.

---

## What was built

15 commits of CCA work, organized into:

**Reusable infrastructure**
- `AspectBus` — priority-ordered FSM-interceptor registry
- 4 aspects on the bus: `DarknessGate`, `BackpackLimit`,
  `MagicWordTeleport`, `ScoreLedger`
- 4 verdict types exercised: consume, transform, observe, pass

**World entities (composed under `Adventure`)**
- `Lamp` (HSM with battery)
- `Player` (alive/dead/permadead)
- `Bird`, `Snake` (cross-FSM coordination)
- `Bear` (5-state HSM with hazard branch)
- `Troll` (3-state, bear-scared cross-FSM)
- `Dwarf` × 5 (parameterized × N with deterministic PRNG)
- `Endgame` (multi-stage HSM with timer)
- `Hint` × 3 (parallel parameterized small FSMs)
- `Dragon` (multi-turn parser dialog as state)

**Total Frame source:** ~3900 lines including comments
**Generated GDScript:** ~10800 lines
**Smoke tests:** 18 files, ~340 checks across them, all PASS
**Map size:** 125 rooms with canonical Crowther+Woods 1977 numbering
**FSM count:** 22 `@@system` declarations

---

## Per-system Frame value scoring

Five-point scale where:

- **5** = Frame transformatively helps; plain GDScript would
        be much worse
- **4** = Frame is a clear win
- **3** = Frame is a wash (about equivalent to plain GDScript)
- **2** = Frame is mild ceremony for marginal benefit
- **1** = Frame is pure ceremony; plain GDScript would be
        smaller and clearer

| System | Score | Why |
|---|---|---|
| `AspectBus` | **4** | $Idle/$Dispatching encodes queue-during-dispatch correctly. The two-state semantic is real; the alternative (a `_dispatching: bool` flag with conditional logic) is the same complexity but hides intent. |
| `Lamp` | **4** | HSM with parent `$On` and three children ($Bright/$Dim/$Out) plus threshold transitions and battery countdown. `is_lit()` and `last_warning` overrides per child are exactly the HSM-inheritance idiom. |
| `Player` | **3** | Three states with simple transitions. Plain GDScript with an enum + a few methods would be ~30 lines vs Frame's 100+. The death-cycle is legible either way. |
| `Bird` | **3** | Four states; the room-dependent transition logic is interesting but small. The save/restore round-trip on $Caged with location=-1 is a real win. |
| `Snake` | **2** | Two states. Morally a boolean. Frame ceremony for ~50 generated GDScript lines. |
| `Bear` | **5** | Five states with a branching hazard ($Hungry × take_chain → $Attacking) and a linear progression that's exactly what state machines are for. The "feed before unchaining" rule is encoded as state and is impossible to forget. |
| `Troll` | **2** | Three states but mostly boolean ("blocking? yes/no/no-because-paid"). Frame doesn't earn much. |
| `Dwarf` × 5 | **4** | Parameterized-with-multiple-instances is a real Frame feature. Per-dwarf seed for deterministic PRNG round-trips through `@@[persist]` cleanly. The if-ladder in `_dispatch_to` is the only blemish. |
| `Endgame` | **5** | Four-state phase machine with a state-variable timer that survives `@@[persist]`. The `$.timer` round-trip on save/restore-mid-$Closing is the headline persistence test in CCA. Hardest to express well in plain GDScript. |
| `Hint` × 3 | **4** | Parallel parameterized small FSMs. Each hint advances independently; observe(true)/observe(false) streak-and-reset is a clean shape; per-hint state survives serialization without thinking about it. |
| `Dragon` | **4** | Multi-turn parser dialog as state. $Asked encodes "we're mid-question." The alternative — a boolean "awaiting_yes_no" flag — works but is the same flag-on-base smell that motivated the aspect bus pattern. |
| `DarknessGate` | **2** | Single state; Frame is ceremony around a function with a counter. |
| `BackpackLimit` | **3** | Single state but with non-trivial counter state, and the consume-verdict pattern is enabled by being on the bus. The bus is what earns its keep here, not the FSM. |
| `MagicWordTeleport` | **3** | Single state; the room-pair table makes it a legitimate small system, but the FSM scaffolding doesn't help. |
| `ScoreLedger` | **2** | Single state. Telemetry counter dressed as a state machine. |

**Distribution:** 3 systems at 5/5, 4 at 4/5, 5 at 3/5, 4 at 2/5,
0 at 1/5.

The mode is 3 (wash) — Frame neither hurts nor helps for the
median CCA system. The peak is 5 (Bear, Endgame) where the
state semantics are doing real load-bearing work.

---

## What Frame demonstrably did well

### 1. `@@[persist]` across composition is a real win

`Adventure.save_state()` round-trips the entire world tree
(Adventure + Lamp + Player + Bird + Snake + Bear + Troll +
Dwarf×5 + Endgame + Hint×3 + Dragon + AspectBus + 4 aspects)
in **one call**. Hand-rolling that would be ~200 lines of
serialization boilerplate distributed across the systems.

The framepiler dev build's `@@[persist]` codegen is genuinely
production-quality once Issues #1 and #2 (documented in
`FRAMEC_BUGS.md`) were fixed.

### 2. State variables surviving push$/pop$ AND save/restore

The Endgame's `$.timer` and the Bird's pushed-compartment
behavior demonstrated that Frame's state-stack semantics
**compose with persistence**. A saved game in mid-$Closing
restores into the same state with the same timer value — and
the bird-released-then-saved test path verified that pushed
compartments under Adventure's $Playing also round-trip.

This is the single most expensive thing to engineer correctly
by hand and Frame ships it.

### 3. The aspect-bus pattern over Frame

The four-verdict bus (consume / transform / observe / pass) is
a Frame *application* — not a Frame feature, but cleanly
expressible with Frame primitives. It decomposed CCA's cross-
cutting concerns (darkness, inventory limit, magic words,
scoring) cleanly. The bus + aspects together are ~250 lines
of Frame; the alternative would be `if`-ladders woven through
Adventure's verb dispatch and would have grown sprawly fast.

### 4. Cross-FSM coordination through the orchestrator

Bird → Snake (release-bird-kills-snake) and Bear → Troll
(release-bear-scares-troll) are both expressed as: each NPC
owns its state transitions; Adventure observes and reaches
across to call dependent NPCs. This pattern is not unique to
Frame, but Frame's composition (named domain fields with
auto-traversal) made the orchestrator feel natural rather than
bookkeeping-heavy.

---

## What Frame demonstrably *didn't* help with

### 1. Single-state aspects

DarknessGate, MagicWordTeleport, ScoreLedger are each a
single state with a single method. The `@@system` /
`machine:` / `$Active { ... }` envelope adds ~30 lines
of generated dispatch code per aspect for zero semantic value.
A plain GDScript class with one `try_handle()` method would
be 15 lines instead of 50.

The bus *itself* benefits from being an FSM ($Idle/$Dispatching).
The aspects on it mostly don't.

### 2. NPCs with 2-3 trivial states

Snake (2 states), Troll (3 states with mostly boolean queries)
do not benefit meaningfully from Frame. The save-restore
integration is nice but minor. An enum + a few functions
would have been roughly equivalent.

### 3. Adventure's verb dispatch and orchestration code

The `do_command` body is procedural GDScript-flavored Frame:
a while loop walking aspects, branches per verdict, an
if-ladder routing names to systems. Wrapping it in
`$Playing { do_command { ... } }` adds zero clarity. The
algorithm is the same procedural code you'd write outside
Frame. The state-machine envelope around it is dead ceremony.

### 4. Generated code bloat

The `cca.gd` output is ~7000 lines of GDScript for ~1500
lines of hand-written Frame source. The ratio is ~4.7×. Most
of that is dispatcher + compartment + serialization
machinery. For runtime debuggability, you read generated
code; for source-of-truth, you read Frame. The two-language
shadow is real overhead.

---

## Comparison: hypothetical CCA in plain GDScript

What would the same architecture look like without Frame?

**Adventure**: a GDScript class with a `do_command(verb, noun)
-> String` method, a list of `aspect` interceptors (plain
classes implementing `try_handle`), and the same `_verb_look`
/ `_verb_take` / etc. helper methods. Procedural orchestration
code is identical.

**Aspects**: each is `class XAspect: func try_handle(e):
return {...}`. ~15 lines each instead of ~50 in Frame. **4× LOC win.**

**NPCs (Lamp / Player / Bird / Snake / Bear / Troll / Dragon)**:
each is a class with an enum state, methods that switch on
state, and per-class `to_dict()` / `from_dict()` save methods.
Roughly the same total LOC as the Frame versions but with
hand-rolled persistence (~15 lines per class × 8 systems =
**~120 lines of save boilerplate** that Frame eliminates).

**Dwarf × 5**: 5 instances of the same class. Plain GDScript
handles this trivially. The `@@[persist]` auto-traversal of
named domain fields is replaced by a `for d in [d1,d2,d3,d4,d5]:
d.from_dict(...)` loop in `from_dict` — ~10 lines of save
boilerplate. **Modest Frame win.**

**Endgame**: a state-machine-shaped class. With an enum and
a `match self.state` in `tick()`, this is ~80 lines of plain
GDScript, vs Frame's ~120 lines of source. **Wash.** The
state semantics are equally clear in either notation; Frame's
$.timer-survives-push is the differentiator if you save/load
mid-$Closing, which costs ~10 lines to hand-roll.

**Hint × 3**: 3 instances of a small class. Same as Dwarves:
plain GDScript handles this fine; Frame's persistence saves
~30 lines of save boilerplate across the three.

**Bear**: a 5-state machine with a branching hazard. Frame's
`$Hungry { feed: -> $Tame; take_chain: -> $Attacking }` is
genuinely clearer than `match state: HUNGRY: if action == "feed":
state = TAME ...`. **Frame win.**

**Net hand-rolled estimate:** ~1200 lines of plain GDScript
for the same architecture. Frame ships ~1500 lines of source
to express the same thing, but eliminates ~150-200 lines of
serialization boilerplate that the GDScript version would
need. **Roughly a wash on lines of code, with Frame being
clearer in 5-6 hot spots and equivalent or worse in 8-9.**

The framec maturity costs (Issues #1 and #2 hit during this
session, the framepiler-dev-build requirement) are real but
small now that they're documented.

---

## When to use Frame for adventure games

**Reach for Frame when:**

- Your game has multi-stage timed phases (Endgame).
- You have NPCs with 4+ meaningful states and branching
  transitions (Bear).
- You have many parameterized instances of the same system
  (Dwarves × 5, Hints × 3).
- You need save/restore across composition.
- You have multi-turn parser dialogs whose context spans
  commands (Dragon's $Asked).

**Don't reach for Frame when:**

- The system has 1-2 states. Use a boolean.
- The system is a single function with a counter. Use a class.
- The system's only meaningful behavior is data lookup.
  Use a Dictionary.

This is a 60/40 split for CCA, leaning slightly Frame-positive.
For arcade games (Stealth, Asteroids, Pac-Man), the same
heuristic puts ~80% of the systems on the Frame side. CCA is
genuinely a less Frame-shaped genre, but not unfit.

---

## Status: canonical scope complete (as of commit `9d31999`)

After the initial evaluation (drafted at commit `c274799`),
the rest landed in three rounds:

**Round 1 — playable** (commit `b1658c6`):
- Pirate FSM
- Treasures × 5 (subset)
- 12-room maze in driver
- Parser with synonym table
- Godot text-adventure UI

**Round 2 — canonical scope** (commit `a5f92f5`):
- 22-room maze (gold, silver, diamonds, jewelry, pearl on
  the surface route; vase, eggs, trident, emerald, spices,
  chest, pyramid, rug, coins, statuette in the deep-cave
  loop accessible via the troll bridge)
- Treasures × 15 (full canonical inventory)
- Room descriptions upgraded to canon-faithful prose

**Round 3 — verbs + scoring** (commit `9d31999`):
- EXAMINE / READ / THROW verbs
- DarknessGate gates "read" alongside "look"/"examine"
- Real CCA scoring breakdown: treasure_score (sum of
  deposited values), visit_score (one per unique room),
  hint_penalty (-2 per accepted hint), endgame_score (+50
  for successful detonation)
- SCORE driver command renders the breakdown

End-to-end smoke test (`/tmp/test_cca_full.gd`) walks the
canonical solve path through all 15 treasures, exercises
every verb, drives endgame timer to repository, detonates,
and verifies the scoring breakdown sums correctly. PASS.

CCA can be played end-to-end:

```bash
cd cca
FRAMEC=…/framepiler/target/release/framec ./build.sh
godot --path godot/ scenes/main.tscn
```

The canonical solve path is verified by an end-to-end smoke
test (`/tmp/test_cca_playthrough.gd` — 33 checks, PASS):
XYZZY into debris, light lamp, take gold, deposit; PLUGH to Y2,
take bird; release at snake; attack dragon (yes); take diamonds;
feed bear, take chain; drop at troll; take jewelry. Plus
mid-game save/restore preserves NPC states.

**Round 4 — canonical mechanics** (commit `0b7ced3`):
- Vase fragility: `Treasure` got a `fragile` param, a new
  `$Broken` state, and `drop()` checks the room — outside
  the well house the vase shatters and value goes to 0.
- Eggs incantation: new `EggsIncantation` 4-state FSM
  (`$Idle` → `$WaitingFie` → `$WaitingFoe` → `$WaitingFoo`
  → `$Idle`). Adventure observes the foo→Idle transition
  and calls `eggs.reappear()` to put them back in the
  giant room. Off-canon words break the chant and reset.
- Bear-attacks-player: `Adventure._verb_take("chain")`
  inspects bear state — if `$Hungry`, it transitions bear
  to `$Attacking` and calls `player.die()`.
- Dwarf-attacks-player: per-turn `_maybe_dwarf_attack`
  tick action — each dwarf in the player's room rolls
  via its own deterministic PRNG and (on hit) sets
  `dwarf_axe_flag` and calls `player.die()`.
- Driver resurrection prompt: dead player triggers a
  yes/no prompt; YES calls `player.revive()` and bumps
  the deaths counter; the 4th death goes `$Permadead`
  and ends the run.
- Save/restore round-trips the new state cleanly,
  including mid-death and the eggs-chant FSM compartment.

A new `/tmp/test_cca_mechanics.gd` smoke test (28 checks,
PASS) covers vase-shatters, vase-deposit-survives, the
full FEE/FIE/FOE/FOO chant, broken-chant reset, bear-
kills-player, deterministic dwarf-axe-throw, the
resurrection cycle, permadeath after the 4th death, and
save/restore mid-death-prompt.

**Round 5 — fissure puzzle + closing crescendo** (commit `d44bb5b`):

- New `CrystalBridge` 2-state FSM (`$NoBridge` ↔ `$Bridge`)
  toggled by `wave()`. Adventure brokers the cross-cutting
  context: the bridge `wave()` only fires when the player
  is at the fissure AND carrying the rod. Otherwise the
  player gets a flavored deflection.
- New `WAVE` verb on Adventure dispatch.
- Rod added as a non-treasure item: domain `rod_carried`/
  `rod_location`, integrated into `_verb_take("rod")` /
  `_verb_drop("rod")` / `_verb_look` overlay.
- Three new rooms added to the driver maze: room 23 (small
  pit, north of Y2), room 24 (the fissure itself), room 25
  (hall of mirrors, far side). Room 24's east exit is
  driver-gated by `bridge_built()`.
- Closing-warning crescendo: while in `$Closing`, the driver
  surfaces three escalating messages at timer thresholds
  25 / 15 / 5 (each fires once), giving the player a sense
  of the cave winding shut rather than one alert and silence.
- Save/restore round-trips the new bridge FSM compartment
  and rod state.

A new `/tmp/test_cca_bridge.gd` smoke test (20 checks, PASS)
covers wave-without-rod, take rod, wave-elsewhere, wave-at-
fissure (build), wave-again (toggle off), wave-non-rod,
save/restore mid-bridge-built, and rod-drop-stays-where-
dropped.

**Round 6 — full canonical room scope** (commit `90be493`):

The room count goes from 25 (compressed, every CCA archetype
present) to 125 (full canonical Crowther+Woods 1977 numbering).
The world model now matches canon: the surface descent through
the slit and grate, the Hall of Mists hub, both mazes (twisty
passages all alike + all different), Witt's End, the Reservoir,
the Treasury, the cliff-and-iron-ladder descent, the Vending
Machine Room, and the canonical surface forest grid.

This round is **pure data, zero new architecture** — the
existing 20 `@@system` declarations and aspect bus handle the
expanded map without modification. Save/restore continues to
round-trip the entire world. The point of the round is to show
that the Frame architecture *scales* from 25 to 125 rooms
without growing the FSM surface.

Phases:

- A: Renumber existing 25 rooms to canon (commit `e01e114`)
- B: Surface block 2-10 (commit `3f3868f`)
- C: Mist + King hall + beanstalk + slab (commit `5125a8b`)
- D: Mazes + Witt's End + side passages (commit `0fac7e8`)
- E: Bedquilt extensions + reservoir + treasury + cliff +
     forests (commit `96f0494`)
- F: Vending Machine Room + iconic remainder (commit `2164b90`)

The grate is described as "swung open" rather than gated —
adding a Grate FSM (locked/unlocked + keys) would replicate
the `CrystalBridge` shape exactly with no new demonstration
value. The maze of twisty passages is described with canonical
text (all 8 rooms identical, plus 8 more "all different") but
uses linear topology rather than the canon non-Euclidean
maze-trap mechanic — that would be a sub-system of its own.

**Round 7 — canon-completion patches** (commits `dfc6e09`,
`4bd3a0e`, `8336dc1`):

Three small follow-ups that finish the canon-puzzle list and
restore one canonical movement nuance.

- **7a — Grate + keys puzzle** (`dfc6e09`). New `Grate` 2-state
  FSM ($Locked / $Unlocked) with a guarded `unlock(have_keys)`
  transition; new `keys` non-treasure item (lives in well house);
  new UNLOCK / OPEN / LOCK verbs. Architecturally identical in
  shape to `CrystalBridge` — pure canon-completion, not new
  Frame-pattern demonstration.
- **7b — Bird-into-Plover refusal** (`4bd3a0e`). Pre-move guard
  in `_verb_move`: if the destination is room 41 (Plover) and
  the player is carrying the bird, the bird flutters free in
  the player's current room before the move completes. Cross-
  cutting context lives in Adventure (the MagicWordTeleport
  aspect stays bird-unaware), same orchestrator pattern as
  bird→snake / bear→troll.
- **7c — Non-Euclidean maze rearrangement** (`8336dc1`). Pure
  data change in `driver.gd` — the rooms 50-57 (twisty passages
  all alike) now have non-uniform exit topology where going
  "north" from two identical-looking rooms lands you in
  different places, and some directions are missing entirely.
  The canon CCA puzzle (drop items as breadcrumbs to map the
  maze) is restored without any FSM changes.

**Round 8 — Vending Machine** (commit `cd1fda2`):

The Vending Machine Room (95) is now functional. Insert the
rare-coins treasure to receive fresh lamp batteries — at the
cost of the points the coins would score by depositing them
at the well house. Genuine puzzle decision: trade points for
a playthrough that fits inside the lamp's battery window.

This round adds a new Frame demonstration pattern:
**consume-an-item-as-side-effect**. The previous patterns
were state-toggle (CrystalBridge / Grate), relocate
(Pirate / Treasure), or transition-only. The Vending Machine
*removes* the coins from play entirely while triggering a
cross-FSM lamp refresh.

- New `@@system VendingMachine` ($Loaded / $Empty) with
  guarded `insert(have_coins)` transition.
- New INSERT verb (and USE alias).
- `_verb_insert`: snapshots before-state, defers to
  `vending.insert(have_coins)`. On success: drops coins from
  inventory, calls `coins.reappear(0)` to relocate them out of
  bounds (no `_verb_look` overlay matches room 0;
  `treasures_deposited()` doesn't count them), and calls
  `lamp.refresh()`.
- Lamp.$On now has a default `refresh()` handler — top up
  battery, drop to $Bright. Previously refresh was only
  defined on $Off and $Out, so refreshing a still-on lamp
  was a silent no-op. The vending machine works while the
  lamp is still on, so the inheritance fix matters.
- New `/tmp/test_cca_vending.gd` (24 checks, PASS).

What's still skipped vs canonical Crowther/Woods CCA:

(none of architectural significance — only the Plover-bird
detail differs from canon: ours has the bird flutter free in
Y2; canon CCA has the bird get "uncoordinated" / vanish, with
the room itself becoming inaccessible if the bird is brought
in. Functionally close enough that the puzzle plays the same
way.)

## Final per-chapter takeaway

For an article on "Frame for interactive fiction":

- **Lead with Bear, Endgame, Dragon** — these are the three
  systems where Frame is unambiguously the right tool.
- **Show the parameterized × N pattern** with Dwarves and
  Hints — same shape, different domain.
- **Show the cross-FSM coordination** with Bird→Snake and
  Bear→Troll — the orchestrator pattern that keeps each NPC
  testable in isolation.
- **Don't overclaim on the small NPCs** — Snake, Troll,
  ScoreLedger, etc. would be roughly equivalent in plain
  GDScript. Frame neither helps nor hurts there.
- **Aspect bus is the architectural payoff** — it's the
  pattern over Frame, and it's the one that scales as the
  game accumulates cross-cutting concerns. Article-worthy on
  its own.

The framec maturity costs (Issues #1 and #2) were real and
were fixed mid-session. Cargo release-skew (Issue #3) is the
remaining friction.

## Recommendation

The chapter on CCA-in-Frame is now writeable from this
document, the in-file comments, the eight smoke tests, and the
playable demo. The architecture is honest, the wins are
identified, the limits are acknowledged.
