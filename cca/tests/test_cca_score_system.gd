extends SceneTree

# ============================================================
# test_cca_score_system.gd
# ============================================================
# Phase C score-system canon-fidelity audit.
#
# CCA's score breaks down into five components, all summed into
# real_score (returned by fsm.score()):
#   score_treasures — sum of deposited-treasure get_value() —
#                     covered by test_cca_treasure_values.gd.
#   score_visits    — +1 per distinct room first-visited.
#   score_hints     — negative; per-hint canon cost (section 11).
#   score_endgame   — BLAST outcomes + detonate bonus. The setup
#                     to reach $InRepository requires depositing
#                     15 treasures and ticking through $Closing;
#                     deferred to an integration test rather than
#                     this focused audit.
#
# Methodology: each component gets a focused test that builds a
# fresh FSM, exercises the component once, and asserts the
# score-delta matches canon.
#
# IMPORTANT: this audit must call fsm.score() (= real_score, the
# full breakdown) not fsm.total_score() (treasures-only). The
# distinction was confused in an earlier draft — that confusion
# was itself a real bug in the driver's victory-prose final-score
# display, surfaced by this audit.
# ============================================================

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

func _init():
    print("=== CCA score-system canon audit ===")
    print("")
    _test_visit_score()
    _test_hint_costs()
    print("")
    if failures == 0:
        print("PASS — score-system components match canon section-11")
        quit(0)
        return
    print("FAIL — %d score divergence(s) from canon" % failures)
    quit(failures)

# Each canon room first-visit awards +1 point. Visit bookkeeping
# fires inside the FSM's tick handler — we have to tick after
# moving.
func _test_visit_score():
    print("--- Visit score ---")
    var fsm = Cca.new()
    fsm.setup_default_aspects()
    fsm.tick()                 # initial visit to canon-start
    var s0: int = fsm.score()
    fsm.player.move_to(2)
    fsm.tick()
    var s1: int = fsm.score()
    fsm.player.move_to(4)
    fsm.tick()
    var s2: int = fsm.score()
    fsm.player.move_to(2)      # re-visit
    fsm.tick()
    var s3: int = fsm.score()
    _assert("first move to 2: +1",      s1 - s0, 1)
    _assert("second move to 4: +1",     s2 - s1, 1)
    _assert("revisit to 2: 0",          s3 - s2, 0)

# Canon section-11 cost column: per-hint penalty when accepted.
# Fixed 2026-05-18 — implementation hardcoded -2 for all hints
# rather than per-canon costs.
func _test_hint_costs():
    print("--- Hint costs (canon advent.dat section 11) ---")
    var expectations: Dictionary = {
        "cave":   2,
        "bird":   2,
        "snake":  2,
        "maze":   4,
        "plover": 5,
        "witts":  3,
    }
    for name in expectations.keys():
        var cost = expectations[name]
        var fsm = Cca.new()
        fsm.setup_default_aspects()
        # Force the hint into the eligible state. Push observe()
        # past every canon threshold (max is 10 for cave).
        var hint = _hint_instance(fsm, name)
        if hint == null:
            _assert("%s hint resolvable" % name, false, true)
            continue
        # Canon thresholds: cave=4, bird=5, snake=8, maze=75,
        # plover=25, witts=20. Loop to 80 to cover the max.
        for _i in range(80):
            hint.observe(true)
        var s_before: int = fsm.score()
        fsm.request_hint(name)
        var delta: int = fsm.score() - s_before
        _assert("%s hint cost (canon %d)" % [name, cost], -delta, cost)

func _hint_instance(fsm, name: String):
    match name:
        "cave":   return fsm.cave_hint
        "bird":   return fsm.bird_hint
        "snake":  return fsm.snake_hint
        "maze":   return fsm.maze_hint
        "plover": return fsm.plover_hint
        "witts":  return fsm.witts_hint
    return null

func _assert(label: String, observed, expected) -> void:
    if observed == expected:
        print("  [OK] %s" % label)
    else:
        print("  [FAIL] %s — expected %s, observed %s" % [
            label, str(expected), str(observed)])
        failures += 1
