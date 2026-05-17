extends SceneTree

# ============================================================
# test_cca_state_space.gd
# ============================================================
# Deterministic state-space search over CCA's reachable state
# graph. See cca/docs/rfcs/rfc-0001.md for the design.
#
# This test is OPT-IN — not part of the default per-commit
# suite. It runs longer than a unit test and exercises the
# search-harness machinery itself. Invoke directly:
#
#   godot --headless --path godot/ --script tests/test_cca_state_space.gd
#
# First-pass coverage: directions-only BFS with room + inventory
# + NPC-state hash. Future iterations layer in object verbs,
# magic-word teleports, and additional invariants.
# ============================================================

const StateSpace = preload("res://scripts/state_space.gd")

func _init():
    print("=== CCA state-space search (RFC-0001 Phase B) ===")

    var s = StateSpace.new()
    s.seed = 42
    # Conservative cap for the first-pass test — surface-area
    # navigation from room 1 reaches ~10-15 rooms before bumping
    # into gated doors / NPCs that block further direction-only
    # exploration. 500 is generous headroom.
    s.max_states = 500
    s.check_save_restore = true

    s.run()
    s.report()

    var failures: int = s.violations.size()
    if failures == 0:
        print("PASS — %d states visited, no invariant violations" % s.states_visited)
        quit(0)
    else:
        print("FAIL — %d invariant violations across %d visited states" % [failures, s.states_visited])
        quit(failures)
