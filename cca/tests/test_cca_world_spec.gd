extends SceneTree

# ============================================================
# test_cca_world_spec.gd
# ============================================================
# Phase C Layer 2 — canon-fidelity check for item placements.
#
# Builds a fresh Cca FSM and asserts every spec'd item is at the
# canon-declared room. The spec lives in
# cca/godot/scripts/world_spec.gd; this test is the
# verification-against-spec half of the model-based testing pair.
#
# Why this matters: the probe and the unit tests can both pass
# while the FSM's item-init code drifts away from canon. This
# test catches that drift at the smallest possible scope — a
# fresh world before any commands.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const WorldSpec = preload("res://scripts/world_spec.gd")

func _init():
    print("=== CCA world-spec init check (Phase C Layer 2) ===")
    print("")

    var fsm = Cca.new()
    fsm.setup_default_aspects()
    # Note: we deliberately do NOT call wake_dwarves() — dwarves
    # don't affect item placement and waking them perturbs the
    # FSM's per-NPC RNG state we don't want to depend on here.

    var violations: Array = WorldSpec.check_initial_placements(fsm)

    print("Items checked:    %d" % WorldSpec.ITEM_SPEC.size())
    print("Init violations:  %d" % violations.size())
    print("")

    if violations.is_empty():
        print("PASS — every spec'd item is at its canon-declared room")
        quit(0)
        return

    print("--- Violations ---")
    for v in violations:
        print("  %s (%s): expected room %d, observed %d" % [
            v.noun, v.kind, v.expected, v.observed])
    print("")
    print("FAIL — %d item(s) diverge from canon spec" % violations.size())
    quit(violations.size())
