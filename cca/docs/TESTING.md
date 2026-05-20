# CCA Testing

This document explains what the CCA test suite covers, the
methodology each kind of test follows, how the architecture
evolved, and how to run the suite.

## At a glance

```
89 tests in cca/tests/test_cca_*.gd, runnable in two modes:

  Pre-commit / dev iteration (~5 min, 78 tests):
    CCA_SMOKE=1 ./run_tests.sh --fast

  Full coverage (~35 min, all 89 tests):
    ./run_tests.sh
```

The pre-commit hook runs the fast mode automatically when
`frame/`, `driver`, or `tests/` files change. Override:
`PRE_COMMIT_SKIP_TESTS=1`. The slow set (8 BFS/fuzzer tests
that take 2-4 min each) runs on demand and in CI.

## Canon coverage today

**140 / 140 canon rooms** have at least one test covering their
canon-defining behavior, split into two complementary checks:

- **134 / 140** rooms reached as visited state-graph nodes via
  the multi-seed UNION BFS audit
  (`test_cca_journey_tree_audit_union`). BFS frontier-expands
  from five seeds: `canonical_journey:SnakeGone`,
  `BearReleased`, `InRepository`, plus the two extension
  journeys `PlantUnlock:PlantHugeGrown` and
  `RustyDoorUnlock:AtCanon91`.
- **6 / 6** transient-prose rooms (`21, 22, 31, 32, 89, 90`)
  verified by canon trigger in `test_cca_transient_prose`.
  These rooms have no canon-topology source — they aren't
  walkable destinations; they're message-condition rooms the
  FSM uses as prose targets.

Reachability is necessary but not sufficient. A separate
**completability** check (`test_cca_journey_completable`)
proves all **32 / 32** canonical milestones are resumable to
victory: restore each milestone's save-state snapshot, replay
the remaining journey, assert it reaches `$Won`. This is the
"save mid-game, reload, still finish" property and a softlock
detector — it asks "can you still WIN from here?" where the
coverage audits only ask "can you GET here?".

## Test categories

The 89 tests split into four methodology layers, ordered by
proximity to the player experience:

### Layer 1 — FSM-direct unit tests (~70 tests)

The bulk of the suite. Each test exercises a specific canon
mechanic by driving the Adventure FSM directly:

```gdscript
var adv = Cca.new()
adv.setup_default_aspects()
adv.player.move_to(13)              // bird chamber
adv.do_command("take", "bird")
_expect("bird now carried", adv.player.carrying(adv.BIRD_ID), true)
```

These run in milliseconds each, assert on FSM state, and cover
the specific puzzle / NPC / verb logic the test is named after.
Examples: `test_cca_lamp`, `test_cca_pirate`, `test_cca_dragon`,
`test_cca_dwarf_canon`, `test_cca_vending`, `test_cca_witts_end`.

### Layer 2 — Canonical journey FSM-driven player-UX test

`test_cca_canonical_journey.gd`. Walks the canonical CCA happy
path end-to-end through the **real Driver** — parser, FSM
dispatch, per-turn tick, log buffer. Every command is piped
through `Driver._process_input` exactly as if the player had
typed it.

The journey itself is described as a Frame state machine in
`cca/frame/canonical_journey.fgd` — 33 milestone states from
`$AtRoad` to `$Victory`. Each state declares the commands a
real player would type to arrive there, the expected room, and
substrings that MUST or MUST NOT appear in the driver's log.
The harness walks the FSM and asserts per state.

### Layer 3 — Drift / structural checks

- `test_cca_topology`: per-room canon-fidelity audit over the
  hand-written `topology.gd` table (140 rooms aligned with
  Crowther/Woods 1977 travel-table).
- Pre-commit drift detector (`cca/scripts/check_cca_drift.py`)
  compares `driver.gd` against the arcade's `cca_main.gd`
  mirror, catching unauthorized divergences before commit.
- Parse-check on every changed `.gd` file via `godot
  --check-only`.

### Layer 4 — State-space BFS + journey-tree audits

The newest layer, built across two RFCs over the V1.2-V1.3 arc.
It answers a question Layers 1-3 deliberately don't: **is any
sequence of commands from start a state-space invariant
violation, and how much of canon does the BFS-reachable set
cover?**

Two test families:

**Single-milestone BFS** (`test_cca_state_space*.gd`):
canonical-start BFS plus several milestone-seeded variants
(LampLit, SnakeGone, DragonDead, TrollPaid, BearFed,
ChainTaken, BearReleased, GoldDeposited, InRepository).
Each seeds a save-state snapshot, then frontier-expands
through real `Driver._process_input` calls, asserting
invariants at every state. Surfaces bugs the single-thread
canonical journey can't: deposit/score counter divergence,
inventory inconsistency, save-restore round-trip drift.

**Journey-tree audits** (`test_cca_journey_tree_*.gd`):
the convergence-loop pattern below. The single-seed audit
(`audit.gd`) seeds from BearReleased and classifies every
unreached canon room by *why* it's unreached
(gate-closed / gate-redirects / gate-passable-but-unreached /
prerequisite-chain / unreachable). The union audit
(`audit_union.gd`) BFS-expands from a curated set of seeds
+ extension journeys, then reports per-seed unique
contributions and union coverage. The plant / rusty-door
unlock tests prove the extension-journey pattern works.

## The journey-tree convergence loop

The core architectural idea, built across this session:

```
canonical_journey (Frame FSM, 33 milestones)
    │
    ├─ adapter → JourneyTree as the root journey
    │
    ├─ Extension journeys branch off any milestone:
    │     • PlantUnlock      (parent=BearReleased)
    │     • RustyDoorUnlock  (parent=PlantHugeGrown)
    │     • ... (future)
    │
    └─ Each branch ends at a snapshot the BFS expands from
```

A journey is a **named DFA path** — a fixed sequence of player
commands that bridges from a parent milestone to a new
milestone, optionally with FSM-direct shortcuts for state the
canon-walk doesn't naturally produce (e.g. filling a bottle
with oil from the well-house). BFS from each milestone's
snapshot explores the *local* reachable graph; the union
across all snapshots is the canon-coverage measurement.

The pattern works because BFS is asymptotic: a single seed
can't penetrate every gated region within a reasonable cap.
Adding journeys that *bridge to* gated regions is dramatically
cheaper than raising the BFS cap.

Types under `cca/godot/scripts/`:

- `journey.gd` — abstract base (`name`, `parent_journey`,
  `parent_milestone`; virtual `apply()` and `milestone_names()`).
- `canonical_journey_adapter.gd` — wraps the Frame-generated
  canonical_journey FSM as the root journey. Handles the
  two FSM-shortcut milestones (`TreasuresFilled` = 13 deposits;
  `InRepository` = 35 ticks) that canonical_journey itself
  reaches via FSM-direct manipulation.
- `extension_journey.gd` — pure-data subclass. `steps: Array`
  of `{name, commands, fsm_pre?}` dictionaries. The optional
  `fsm_pre: Callable` runs before the step's commands —
  documented escape hatch for state that's expensive to reach
  via player commands.
- `journey_tree.gd` — registry + recursive walker.
  `walk_to(driver, registry, "journey:milestone")` resolves the
  parent chain and lands snapshots in a `MilestoneRegistry`.

## Architecture evolution

The architecture grew across ~30 commits, in three arcs:

### Arc 1: Soundness via state-space BFS (RFC-0001)

Initial setup (`1d7b72f`-`95f01eb`): three-layer test
architecture (FSM-direct + canonical journey + drift checker).
Coverage looked clean — 65 tests, all green — but there was an
acknowledged gap: *"Is there any sequence of commands from
start that violates an invariant?"* No layer asked this.

RFC-0001 proposed a state-space BFS: enumerate every
reachable state, assert invariants (room-in-range, score
floor, lamp battery, deposit count, inventory consistency)
at each. First implementation surfaced a real bug
(`0cb79d4` → `ae27dd4`): inventory-on-death. The BFS proved
the gap was real.

Subsequent commits widened the search (`ff38b56`,
`ba73d4a`, `ab71d9d`) and added the canonical-start
frontier-expansion mode (`77c27a8` + `59584a1`).

### Arc 2: Milestone-seeded BFS to penetrate deep states (RFC-0002)

Canonical-start BFS reached only 16 rooms. Most of the cave
sits behind the grate-unlock + lamp-light + nontrivial-
navigation chain that BFS's breadth-first action ordering
can't penetrate within a reasonable cap.

RFC-0002 introduced **milestone-seeded BFS**: walk the
canonical journey to a milestone, snapshot the FSM, then BFS
from that snapshot. `MilestoneRegistry` (introduced in
`ad936b0`) stored snapshots by `"journey_name:milestone"` key.
Coverage at LampLit jumped to ~30 rooms; at deeper milestones
(SnakeGone, DragonDead, BearReleased) it kept climbing.

This arc also surfaced an axe-place inventory bug (`3c1d6ef`)
and the dwarf-wake walker bug (`debac6d`): six milestone-
seeded tests called `wake_dwarves()` which activated dwarves
from turn 1, blocking the journey's own commands.

### Arc 3: The convergence loop and 140/140 canon coverage

The session-arc covered in commits `aadf097` through
`13cfab2` (the 11 commits this session). Sequence:

1. **The journey-tree audit** (`debac6d`, then refined this
   session): walks canonical_journey to a deep milestone,
   then BFS frontier-expands from there, then for each
   unreached canon room classifies *why* it's unreached.
   Categories: gate-blocked, prerequisite-chain, unreachable
   — later refined into runtime-gate-status buckets after
   the classifier was found to be too coarse.

2. **The prompts-state-leak fix** (`aadf097`): the audit
   reported 53/140 rooms reached. Investigation showed BFS
   `restore_state()` rolled the FSM back but **not**
   `driver.prompts` — the PromptDispatcher is a driver-side
   object, not an FSM aspect. One branch dying in BFS left
   `$AwaitingRevive` active; every subsequent branch
   inherited it, and the modal Y/N dispatcher ate every
   non-yes/no verb. The fix was a one-liner: reset
   `driver.prompts` after each `restore_state`. Coverage
   jumped 53 → 104. This is the canonical example of a bug
   hidden in test infrastructure — the audit was "passing
   53/140" for a long time without anyone catching that
   the number was a lie about what BFS could actually do.

3. **Phase 4a — journey-tree data model** (`d64010b`):
   `Journey`, `ExtensionJourney`, `CanonicalJourneyAdapter`,
   `JourneyTree`. Built so the audit could grow new
   extension journeys instead of becoming a monolithic
   hand-rolled walker.

4. **Audit classifier refinement + cap bump** (`10059fd`):
   raised the BFS cap 5000 → 15000 to reach 122 rooms.
   Refined the "gate-blocked" classifier to evaluate gate
   runtime status (open / closed / redirects / passable
   against the seed FSM state), so cleared gates (snake gone,
   dragon dead) stop showing up as unresolved puzzles.
   Probe at cap=30000 also disproved "prerequisite-chain" —
   every flagged room was just queued-but-not-popped under
   the cap.

5. **PlantUnlock** (`5cac0e2`): the first concrete extension
   journey, branching off BearReleased. Walks the canyon
   back through canon 65 to canon 38 (oil-source canon
   water-fill), then to canon 25 (West Pit) for the plant
   pour cycle. BFS from `PlantHugeGrown` reaches canon 26,
   88, 92, 93, 94 — five rooms BearReleased alone can't see.
   Construction also found and fixed an affordance/FSM bug:
   `list_actions_here` advertised room 23 as a water source
   (FSM disagreed) and missed eight real sources.

6. **Multi-seed union audit** (`0628689`, `ffa5ed0`):
   `test_cca_journey_tree_audit_union` BFS-expands from a
   curated set of seeds, then computes the UNION of reached
   rooms. Reports per-seed unique contributions so each
   seed's coverage payload is visible. Started at 130/140
   (SnakeGone + BearReleased + PlantHugeGrown), then 132/140
   after adding InRepository.

7. **Pre-commit speedup** (`e27bb2e`): the full suite was
   ~21 min as the BFS tests grew. Three composing changes
   cut the pre-commit hook to ~5 min:
   - `StateSpace.check_save_restore` default flipped to
     false; `test_cca_state_space` opts in.
   - `CCA_SMOKE=1` env var lowers audit caps (15000 → 2000
     for the single-seed audit; ~85% drop for union).
   - `run_tests.sh --fast` skips a SLOW_TESTS list of 8
     BFS/fuzzer tests.

8. **Death-scenario tests** (`c3d97cf`): bear-take-chain
   at $Hungry and bridge-collapse-with-bear-following.
   Multi-step canon deaths that no other test exercises
   end-to-end via player commands.

9. **RustyDoorUnlock** (`1cb521c`): second extension
   journey, branching off PlantHugeGrown. Climbs out of
   the plant pit to canon 94, FSM-shortcuts oil into the
   bottle (same pattern as canonical_journey's
   TreasuresFilled), pours, walks to canon 95 and 91.
   ExtensionJourney gained an optional `fsm_pre: Callable`
   per step for this kind of state injection. Union
   coverage: 132 → 134.

10. **Transient-prose coverage** (`13cfab2`): the last 6
    canon rooms (21, 22, 31, 32, 89, 90) have no canon-
    topology source. They're message-condition rooms,
    triggered when the player attempts specific actions
    (gold-blocks-the-steps, snake-blocking, plant-not-tall,
    etc.). One rollup test asserts every transient-prose
    canon room fires its message from its canon trigger.
    Brings combined coverage to 140/140.

## What this catches

| Bug class | Caught by |
|---|---|
| Wrong canon msg for a specific verb | Layer 1 |
| Missing room overlay (lamp not visible) | Layer 2 |
| Driver parser drops a motion alias | Layer 2 |
| FSM state machine off-by-one | Layer 1 |
| Topology missing an exit | Layer 3 |
| Driver drift standalone vs arcade | Layer 3 |
| Invariant violation across all reachable states | Layer 4 |
| Affordance/FSM divergence (advertised but not handled) | Layer 4 — surfaced PlantUnlock fill-bottle bug |
| Driver-side state leaks across BFS branches | Layer 4 — surfaced prompts-state-leak |
| Canon room unreachable via known journeys | Layer 4 (union audit gap classifier) |
| Softlock — victory unreachable from a save-point | Completability (`test_cca_journey_completable`) |
| Affordance/FSM list drift (oil/water sources) | `test_cca_affordance_fsm_agree` — surfaced the 79-vs-24 oil-source bug |
| BFS restore-path state leak (regression) | `test_cca_bfs_restore_property` — pins the prompts-leak fix |

The audit's *classification* output is itself a documentation
artifact: when a room is unreached, the report says whether
it's behind a closed gate (Phase 2 extension candidate), a
redirected gate (different-seed candidate), a probabilistic
gate (RNG-budget issue), or a prerequisite-chain (cap-budget
or BFS issue).

## How to run

```bash
cd cca

# Pre-commit / dev iteration (~5 min)
CCA_SMOKE=1 ./run_tests.sh --fast

# Full coverage (~22 min)
./run_tests.sh

# Subset
./run_tests.sh tests/test_cca_lamp.gd tests/test_cca_canonical_journey.gd

# Single test (raw godot, full output)
godot --headless --path godot/ --script "$(pwd)/tests/test_cca_lamp.gd"

# Skip tests in pre-commit
PRE_COMMIT_SKIP_TESTS=1 git commit -m "..."
```

## Writing a new test

A focused mechanic test (Layer 1) is ~30-50 lines:

```gdscript
extends SceneTree

const Cca = preload("res://scripts/cca.gd")
const H   = preload("res://scripts/_test_helpers.gd")

var failures: int = 0

func _expect(label: String, actual, expected) -> void:
    if actual == expected:
        print("  ok   %-44s = %s" % [label, str(actual)])
    else:
        print("  FAIL %-44s = %s (expected %s)" % [label, str(actual), str(expected)])
        failures += 1

func _init():
    print("=== <what this exercises> ===")
    var adv = Cca.new()
    adv.setup_default_aspects()
    # ... arrange ...
    # ... act via adv.do_command(...) ...
    # ... _expect on adv state ...
    if failures == 0:
        print("PASS")
    else:
        print("FAIL")
    quit(failures)
```

A new extension journey is ~80 lines following
`test_cca_journey_tree_plant_unlock.gd` or
`test_cca_journey_tree_rusty_door.gd` — define the journey's
parent + steps + expected new rooms, register it with the
`JourneyTree`, then assert the BFS from the new snapshot
reaches the expected rooms.

The harness (`_test_helpers.gd`) carries shared assertions
and a `make_driver()` helper for tests that need the Driver
rather than the bare FSM.

## Open improvements

Three high-leverage moves identified at the end of the V1.3
arc:

1. **Test-infrastructure invariants.** The prompts-state-leak
   hid behind a passing audit. A cheap cross-check ("BFS
   reached every room canonical_journey visits") would have
   flagged it instantly.
2. **Affordance/FSM divergence detector.** One-shot test: for
   every action `list_actions_here()` emits, verify the FSM
   produces a state change. Catches the room-23 fill-bottle
   class of bug.
3. **Property-based test on the BFS harness.** "Restoring from
   any snapshot then hashing yields the original hash" would
   have caught the prompts-leak. Generalizes to driver-side
   state we don't currently checkpoint.
