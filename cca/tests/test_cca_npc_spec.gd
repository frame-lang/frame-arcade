extends SceneTree

# ============================================================
# test_cca_npc_spec.gd
# ============================================================
# Phase C Layer 3 — canon-fidelity check for NPC initial states.
#
# Builds a fresh Cca FSM and asserts every spec'd NPC starts in
# the canon-declared state. The spec lives in
# cca/godot/scripts/world_spec.gd::NPC_SPEC. This test is the
# verification-against-spec half for the NPC family.
#
# Companion to test_cca_world_spec.gd (which handles item
# placements). Same shape, different domain — the smallest
# possible canon-fidelity check is "a fresh world before any
# commands matches canon."
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const WorldSpec = preload("res://scripts/world_spec.gd")

func _init():
    print("=== CCA NPC-spec init check (Phase C Layer 3) ===")
    print("")

    var fsm = Cca.new()
    fsm.setup_default_aspects()
    # Dwarves intentionally NOT woken — their wake transitions to
    # Stalking, and the NPC spec describes the pre-wake "Hidden"
    # initial. Pirate stays at its own pre-activation state.

    var violations: Array = WorldSpec.check_initial_npc_states(fsm)

    print("NPCs checked:    %d" % WorldSpec.NPC_SPEC.size())
    print("Init violations: %d" % violations.size())
    print("")

    if violations.is_empty():
        print("PASS — every spec'd NPC is in its canon-declared state")
        quit(0)
        return

    print("--- Violations ---")
    for v in violations:
        print("  %s: expected state '%s', observed '%s'" % [
            v.npc, v.expected, v.observed])
    print("")
    print("FAIL — %d NPC(s) diverge from canon spec" % violations.size())
    quit(violations.size())
