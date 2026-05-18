extends SceneTree

# ============================================================
# test_cca_hint_thresholds.gd
# ============================================================
# Locks the hint-eligibility thresholds at canon advent.dat
# section-11 values. Each hint becomes eligible after N
# consecutive `observe(true)` calls where N is the Hint's
# `_create(N)` threshold.
#
# Restored 2026-05-18 to canon values after a session-finding
# review: an earlier draft of cca.fgd had reduced thresholds
# "to keep smoke tests snappy" (10/3/3/5/4/4). That meant the
# shipping game was running with non-canon hint timing and the
# canon-threshold paths were NEVER actually tested. The shortcut
# was a violation of canon-fidelity discipline (tests should
# accommodate the game, not the other way around). Restored to
# canon, this test asserts the canonical values.
# ============================================================

const Cca = preload("res://scripts/cca.gd")

var failures: int = 0

# Canon advent.dat section 11 thresholds (column 2 = "turns to
# trigger"). Verifiable in cca/canon/advent.dat:1758-1768.
const CANON_THRESHOLDS: Dictionary = {
    "cave":   4,
    "bird":   5,
    "snake":  8,
    "maze":   75,
    "plover": 25,
    "witts":  20,
}

func _init():
    print("=== CCA hint-threshold canon-fidelity check ===")
    print("")
    print("Hints checked: %d  (against canon advent.dat section-11)" % CANON_THRESHOLDS.size())
    print("")

    for name in CANON_THRESHOLDS.keys():
        _test_hint_threshold(name, CANON_THRESHOLDS[name])

    print("")
    if failures == 0:
        print("PASS — all hint thresholds match canon section-11")
        quit(0)
        return
    print("FAIL — %d hint threshold(s) diverge from canon" % failures)
    quit(failures)

func _test_hint_threshold(name: String, threshold: int) -> void:
    var fsm = Cca.new()
    fsm.setup_default_aspects()
    var hint = _hint_instance(fsm, name)
    if hint == null:
        _assert("%s hint resolvable" % name, false, true)
        return
    # Initially not eligible.
    _assert("%s: pre-observe not eligible" % name,
        hint.is_eligible(), false)
    # threshold-1 observations: still not eligible.
    for _i in range(threshold - 1):
        hint.observe(true)
    _assert("%s: after %d observes still not eligible" % [name, threshold - 1],
        hint.is_eligible(), false)
    # One more: now eligible.
    hint.observe(true)
    _assert("%s: after %d observes eligible" % [name, threshold],
        hint.is_eligible(), true)

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
