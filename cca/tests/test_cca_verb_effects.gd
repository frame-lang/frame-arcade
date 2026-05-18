extends SceneTree

# ============================================================
# test_cca_verb_effects.gd
# ============================================================
# Phase C Layer 4 — verb-effect canon-fidelity checks.
#
# For each entry in WorldSpec.VERB_EFFECTS, build a fresh Driver,
# apply the spec's setup (place player, give items, optionally
# pre-set lamp/grate state), execute the typed input(s) through
# the real Driver._process_input pipeline, then verify the
# spec's expected post-state matches what the FSM reports.
#
# Each entry is independent — a fresh FSM per check so cross-
# contamination is impossible. That's the model-based-testing
# discipline: declare what canon says, run the action, assert
# the world matches. The test prints PASS/FAIL per entry plus
# a summary.
#
# This is the most ambitious of the four Phase C tests:
# everywhere else we verified static invariants (item placement,
# NPC initial state, treasure values), here we're verifying
# *behaviour* — the action-to-effect mappings that make CCA
# CCA.
# ============================================================

const H = preload("res://scripts/_test_helpers.gd")
const Cca = preload("res://scripts/cca.gd")
const WorldSpec = preload("res://scripts/world_spec.gd")

func _init():
    print("=== CCA verb-effect canon checks (Phase C Layer 4) ===")
    print("")

    var entries: Array = WorldSpec.VERB_EFFECTS
    print("Verb-effects checked: %d" % entries.size())
    print("")

    var failures: int = 0
    for entry in entries:
        var d: H.CapturedDriver = H.make_driver()
        # H.make_driver lights the lamp by default; reset to canon
        # off-state so spec's `lamp` setup field is authoritative.
        if d.fsm.lamp.is_lit():
            d.fsm.lamp.extinguish()

        WorldSpec.apply_setup(d, entry.setup)

        for cmd in entry.input:
            d._process_input(cmd)

        var fails: Array = WorldSpec.verify_expect(d.fsm, entry.expect)
        var status: String = "OK" if fails.is_empty() else "FAIL"
        print("  [%s] %s" % [status, entry.id])
        if not fails.is_empty():
            for f in fails:
                print("        %s" % f)
            failures += 1

    print("")
    if failures == 0:
        print("PASS — every canon verb-effect matches spec")
        quit(0)
        return
    print("FAIL — %d verb-effect(s) diverge from canon spec" % failures)
    quit(failures)
