extends SceneTree

# ============================================================
# test_cca_treasure_values.gd
# ============================================================
# Phase C — treasure-value cross-check.
#
# The spec (world_spec.gd) declares each treasure's deposit value
# (canon 14 points per treasure, 15 treasures, 210 maximum from
# treasures alone). This test verifies that the FSM's
# get_value()-on-deposit math agrees with the spec, treasure by
# treasure.
#
# Methodology: for each spec'd treasure, build a fresh FSM,
# measure total_score(), force-deposit just that one treasure,
# measure total_score() again. Assert the delta equals the
# spec's declared value. Catches the bug class "score-on-
# deposit math drifts from canon" without requiring a full
# playthrough.
#
# Dynamic-spawn treasures (pearl, chest) get a manual reappear()
# at a known room before take+drop — we're testing the
# value-on-deposit invariant, not the spawn mechanics.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const WorldSpec = preload("res://scripts/world_spec.gd")

# Canon well-house room — must match Adventure.DEPOSIT_ROOM.
const DEPOSIT_ROOM: int = 3

# A "safe" room to reappear dynamic-spawn treasures at before
# the test takes them. Any room without weird side-effects works;
# we use room 11 (debris room) which is in the cave and has no
# extra mechanics.
const SAFE_REAPPEAR_ROOM: int = 11

func _init():
    print("=== CCA treasure-value cross-check (Phase C) ===")
    print("")

    var treasures: Array = _treasure_nouns()
    print("Treasures checked: %d" % treasures.size())
    print("")

    var failures: int = 0
    for noun in treasures:
        var spec: Dictionary = WorldSpec.ITEM_SPEC[noun]
        var expected: int = spec.value
        var observed: int = _measure_deposit_delta(noun, spec)
        var ok: bool = (observed == expected)
        var status: String = "OK" if ok else "FAIL"
        print("  %-9s  expected +%d  observed +%d   %s" % [
            noun, expected, observed, status])
        if not ok:
            failures += 1

    print("")
    if failures == 0:
        print("PASS — every treasure's deposit value matches canon spec")
        quit(0)
        return
    print("FAIL — %d treasure(s) diverge from spec'd value" % failures)
    quit(failures)

# Pull the treasure-kind nouns out of the spec. Treasure value
# tests don't apply to non-treasure items.
func _treasure_nouns() -> Array:
    var out: Array = []
    for noun in WorldSpec.ITEM_SPEC.keys():
        if WorldSpec.ITEM_SPEC[noun].kind == "treasure":
            out.append(noun)
    return out

# Build a fresh FSM, deposit exactly one treasure, return the
# score delta. Handles dynamic-spawn treasures by reappear()-ing
# them at a known room first.
func _measure_deposit_delta(noun: String, spec: Dictionary) -> int:
    var fsm = Cca.new()
    fsm.setup_default_aspects()
    var baseline: int = fsm.total_score()
    var t = _treasure_instance(fsm, noun)
    if t == null:
        return -999

    var pickup_room: int = spec.initial_room
    if spec.dynamic_spawn:
        # Manually spawn so we can take + deposit. The reappear()
        # event drops it at the named room; that's enough to
        # exercise the take→deposit pair.
        t.reappear(SAFE_REAPPEAR_ROOM)
        pickup_room = SAFE_REAPPEAR_ROOM

    # Eggs are a special case — their initial-room behavior plus
    # the FEE FIE FOE FOO reappear mechanic mean a plain
    # try_take/try_drop pair works, but we should reset any side
    # effects. For the value test the simple pair is enough.
    var took: bool = t.try_take(pickup_room)
    if not took:
        # Take failed (maybe at wrong room, or in wrong state).
        # Fall back: reappear at safe room and retry.
        t.reappear(SAFE_REAPPEAR_ROOM)
        took = t.try_take(SAFE_REAPPEAR_ROOM)
        if not took:
            return -998

    var drop_outcome = t.try_drop(DEPOSIT_ROOM)
    var delta: int = fsm.total_score() - baseline
    return delta

func _treasure_instance(fsm, noun: String):
    match noun:
        "gold":     return fsm.gold
        "silver":   return fsm.silver
        "diamonds": return fsm.diamonds
        "jewelry":  return fsm.jewelry
        "pearl":    return fsm.pearl
        "vase":     return fsm.vase
        "eggs":     return fsm.eggs
        "trident":  return fsm.trident
        "emerald":  return fsm.emerald
        "spices":   return fsm.spices
        "chest":    return fsm.chest
        "pyramid":  return fsm.pyramid
        "rug":      return fsm.rug
        "coins":    return fsm.coins
        "chain":    return fsm.chain
    return null
