extends SceneTree

# ============================================================
# test_cca_state_space.gd
# ============================================================
# Single-sweep canonical-start BFS over the reachable state
# graph. Every state in `visited` is *player-reachable* — arrived
# at by some sequence of Driver._process_input calls from the
# canonical start.
#
# Rewritten 2026-05-18 from the earlier three-sweep approach:
#
#   OLD: three sweeps with FSM teleport between (surface,
#        well-house-with-items, debris-with-rod). Each sweep
#        proved FSM-reachability per its teleported start, but
#        not player-reachability — a state was in `visited`
#        because we teleported to it, regardless of whether
#        canonical play could reach it.
#
#   NEW: one sweep from canonical start, BFS-expanding via the
#        Driver._process_input pipeline. Player-reachability is
#        proven by construction. States the old sweeps reached
#        via teleport that aren't player-reachable simply don't
#        appear in `visited` — which is the correct answer.
#
# The action source is driver.list_actions_here() (shared with
# probe.gd), filtered to non-wild actions because wild verbs
# almost always produce self-loops in the state graph.
# ============================================================

const StateSpace = preload("res://scripts/state_space.gd")

func _init():
    print("=== CCA state-space search (canonical-start BFS) ===")
    print("")

    var s = StateSpace.new()
    s.seed = 42
    # Cap raised from 2000 (legacy three-sweep total) — canonical-
    # start BFS reaches more states from one seed because frontier
    # expansion crosses gates the teleport sweeps had to skip via
    # pre-staged inventory. Estimated reachable set is in the
    # thousands; 10K is a safety ceiling, not an expected target.
    s.max_states = 10000
    s.run()
    s.report()
    print("")

    if s.violations.is_empty():
        print("PASS — canonical-start BFS clean")
        quit(0)
        return
    print("FAIL — %d invariant violation(s) across reachable states" % s.violations.size())
    quit(s.violations.size())
