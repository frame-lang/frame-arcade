# CCA Testing

This document explains what the CCA test suite covers, the
methodology each kind of test follows, and how to run them.

## At a glance

```
65 tests in cca/tests/test_cca_*.gd, runnable via:
  cd cca && ./run_tests.sh

Time:  ~3-5 minutes (monkey fuzzer runs the longest, ~75-90s)
Gate:  pre-commit hook runs the suite when frame/, driver, or
       tests/ files change. Override: PRE_COMMIT_SKIP_TESTS=1
```

## Test categories

The 65 tests split into three methodology layers, ordered by
proximity to the player experience:

### Layer 1 — FSM-direct unit tests (~60 tests)

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
Pattern proved stable across the V1 canon-fidelity work — the
tests are short, focused, and don't carry harness machinery.

Examples: `test_cca_lamp`, `test_cca_pirate`, `test_cca_dragon`,
`test_cca_dwarf_canon`, `test_cca_vending`, `test_cca_witts_end`.

### Layer 2 — Canonical journey FSM-driven player-UX test (1 test)

`test_cca_canonical_journey.gd`. A single test that walks the
canonical CCA happy path end-to-end through the **real Driver**
— parser, FSM dispatch, per-turn tick, log buffer. Every command
is piped through `Driver._process_input` exactly as if the
player had typed it.

The journey itself is described as a Frame state machine in
`cca/frame/canonical_journey.fgd` — 32 milestone states from
`$AtRoad` to `$Victory`. Each state declares the commands a real
player would type to arrive there, the expected room, and
substrings that MUST or MUST NOT appear in the driver's log
output. The harness walks the FSM and asserts per state.

This is the only test that catches player-visible bugs the
FSM-direct tests can't see — a room description missing an item,
a Y/N prompt firing too early, a custom motion alias the parser
silently drops. Six driver-level bugs were surfaced and fixed
during construction (lamp-not-placed-item, premature-cave-hint,
custom-motion-alias-dropped, `_handle_movement`-crash-on-Array-
gate, take-chain-at-released-bear, gold-blocks-the-steps-route).

Full design in [`CANONICAL_JOURNEY.md`](../CANONICAL_JOURNEY.md).

### Layer 3 — Drift / structural checks (1 + housekeeping)

`test_cca_topology`: per-room canon-fidelity audit over the
hand-written `topology.gd` table (140 rooms aligned with the
Crowther/Woods 1977 travel-table).

The pre-commit hook also runs a non-test drift detector
(`cca/scripts/check_cca_drift.py`) that compares the standalone
`driver.gd` against the arcade's `cca_main.gd` mirror, catching
unauthorized divergences before commit. Plus parse-checking
every changed `.gd` file via `godot --check-only`.

## What's deliberately NOT tested at the player-UX layer

The canonical journey is a **happy path** through the canon.
These edge cases are covered by Layer 1 tests, not by replaying
them through the Driver:

- Multi-dwarf encounter probabilities (`test_cca_multi_dwarf`)
- Pirate steal-and-stash mechanics (`test_cca_pirate*`)
- Witt's End 95/5 bounce probability (`test_cca_witts_end`)
- Hint Y/N prompt flow (`test_cca_hints`)
- Save/restore round-trip across every persisted system
  (`test_cca_save_restore*`)
- Lamp battery countdown to zero (`test_cca_lamp`)
- ~60 minor objects' EXAMINE / READ prose
  (`test_cca_scenery_flavor`, `test_cca_minor_verbs`)

These are stable, isolated mechanics. Walking them through a
canonical-journey commit sequence would add cost without finding
bugs the focused tests don't already catch.

## How the layers complement each other

| Bug type | Caught by |
|---|---|
| Wrong canon msg for a specific verb | Layer 1 (focused mechanic test) |
| Missing room overlay (e.g. lamp not visible) | Layer 2 (canonical journey) |
| Driver parser drops a motion alias | Layer 2 |
| FSM state machine off-by-one | Layer 1 |
| Score off-by-one on a specific deposit | Layer 1 |
| Topology missing an exit | Layer 3 (`test_cca_topology`) |
| Driver drift between standalone/arcade | Layer 3 (drift detector) |

What's NOT in scope of any current layer: **soundness across the
whole reachable state space**. The canonical journey walks one
path. The Layer 1 tests check specific mechanics from teleported
start states. Neither asks "is there *any* sequence of commands
from start that violates an invariant?" That's the gap RFC-0001
proposes to fill.

## How to run

```bash
cd cca

# Full suite (~3-5 min)
./run_tests.sh

# Subset
./run_tests.sh tests/test_cca_lamp.gd tests/test_cca_canonical_journey.gd

# Single test (raw godot invocation, full output)
godot --headless --path godot/ --script "$(pwd)/tests/test_cca_lamp.gd"

# Skip tests in pre-commit
PRE_COMMIT_SKIP_TESTS=1 git commit -m "..."
```

Tests require `godot` on PATH and the generated `.gd` FSM files
in `cca/godot/scripts/` (run `./build.sh` once to populate them
from the `.fgd` Frame source).

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
    // ... arrange ...
    // ... act via adv.do_command(...) ...
    // ... _expect on adv state ...
    if failures == 0:
        print("PASS")
    else:
        print("FAIL")
    quit(failures)
```

The harness (`_test_helpers.gd`) carries shared assertions and a
`make_driver()` helper for tests that need the Driver Control
rather than the bare FSM.
