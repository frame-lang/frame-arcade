extends SceneTree

# State-space exploration of CCA's smaller @@systems.
#
# Uses save_state/restore_state (every @@[persist] system has
# them) to teleport between visited states while doing a BFS of
# the (state, event) graph. Reports:
#   - every discovered state
#   - every transition (with self-loops marked)
#   - dead-end states (no outgoing transition besides self-loop)
#
# This catches a class of bugs that scenario-based smoke tests
# don't: states that are reachable but have no way out,
# documented states that the generated code doesn't actually
# enter, and transitions that landed in unexpected states
# because of comment-shift / framec-quirk bugs.

const Cca = preload("res://scripts/cca.gd")
const StateExplorer = preload("res://scripts/state_explorer.gd")

var failures: int = 0

# Validate that an exploration report matches the expected
# canonical shape of the FSM. Catches:
#   - states the docs claim are reachable but the generated
#     code never reaches (or vice-versa)
#   - new dead-ends introduced by an FSM change
#   - transitions targeting states the explorer didn't
#     discover (would mean save/restore lost the state)
func _validate(report: Dictionary, label: String,
               expected_states: Array,
               expected_dead_ends: Array) -> void:
    var problems: Array = []
    if not report.states.has(report.initial):
        problems.append("initial state %s not in states" % report.initial)
    for t in report.transitions:
        if not report.states.has(t.to):
            problems.append("transition %s -> %s targets unknown state" % [t.from, t.to])
    var got_states: Array = report.states.duplicate()
    got_states.sort()
    var want_states: Array = expected_states.duplicate()
    want_states.sort()
    if got_states != want_states:
        problems.append("states mismatch: got %s, expected %s" % [got_states, want_states])
    var got_dead: Array = report.dead_ends.duplicate()
    got_dead.sort()
    var want_dead: Array = expected_dead_ends.duplicate()
    want_dead.sort()
    if got_dead != want_dead:
        problems.append("dead-ends mismatch: got %s, expected %s" % [got_dead, want_dead])
    if problems.is_empty():
        print("  ok   %s structural checks" % label)
    else:
        print("  FAIL %s structural checks:" % label)
        for p in problems:
            print("    - %s" % p)
        failures += 1

func _init():
    print("=== CCA state-space exploration ===")
    print()

    _explore_bear()
    print()
    _explore_lamp()
    print()
    _explore_plant()
    print()
    _explore_crystal_bridge()
    print()
    _explore_grate()
    print()
    _explore_vending_machine()

    print()
    if failures == 0:
        print("PASS — all explored FSMs match expected shape")
    else:
        print("FAIL — %d failure(s)" % failures)
    quit(failures)

func _explore_bear() -> void:
    var factory = func() -> Variant: return Cca.Bear.new()
    var events = [
        ["feed",       []],
        ["take_chain", []],
        ["drop_chain", []],
    ]
    var report = StateExplorer.explore(factory, events)
    StateExplorer.print_report(report, "Bear")
    _validate(report, "Bear",
        ["hungry", "tame", "following", "released", "attacking"],
        ["attacking", "released"])

func _explore_lamp() -> void:
    # Lamp has 4 canonical states ($Off, $Bright, $Dim, $Out)
    # but $Dim and $Out are only reached by draining the battery
    # over many ticks. The explorer's "one event per state"
    # model finds the lifecycle transitions but not the
    # threshold-driven ones. We validate only the lifecycle
    # subset; the smoke test test_cca_lamp.gd covers the full
    # battery-drain lifecycle separately.
    var factory = func() -> Variant: return Cca.Lamp.new()
    var events = [
        ["light",      []],
        ["extinguish", []],
        ["refresh",    []],
    ]
    var report = StateExplorer.explore(factory, events)
    StateExplorer.print_report(report, "Lamp (lifecycle only)")
    _validate(report, "Lamp", ["off", "bright"], [])

func _explore_plant() -> void:
    var factory = func() -> Variant: return Cca.Plant.new()
    var events = [
        ["water", []],
    ]
    var report = StateExplorer.explore(factory, events)
    StateExplorer.print_report(report, "Plant")
    # Canon over-water cycles huge → tiny (advent.for 9132,
    # PROP(PLANT) = MOD(PROP+2, 6)), so there's no dead-end now.
    _validate(report, "Plant",
        ["tiny", "tall", "huge"],
        [])

func _explore_crystal_bridge() -> void:
    var factory = func() -> Variant: return Cca.CrystalBridge.new()
    var events = [
        ["wave", []],
    ]
    var report = StateExplorer.explore(factory, events)
    StateExplorer.print_report(report, "CrystalBridge")
    _validate(report, "CrystalBridge", ["no_bridge", "built"], [])

func _explore_grate() -> void:
    var factory = func() -> Variant: return Cca.Grate.new()
    var events = [
        ["unlock", [false]],
        ["unlock", [true]],
        ["lock",   []],
    ]
    var report = StateExplorer.explore(factory, events)
    StateExplorer.print_report(report, "Grate")
    _validate(report, "Grate", ["locked", "unlocked"], [])

func _explore_vending_machine() -> void:
    var factory = func() -> Variant: return Cca.VendingMachine.new()
    var events = [
        ["insert", [false]],
        ["insert", [true]],
    ]
    var report = StateExplorer.explore(factory, events)
    StateExplorer.print_report(report, "VendingMachine")
    _validate(report, "VendingMachine", ["loaded", "empty"], ["empty"])

func _explore_exit_dialog() -> void:
    # ExitDialog lives in arcade/ — only available when running
    # against the cabinet's compiled scripts. Skip if we can't
    # find it.
    if not ResourceLoader.exists("res://scripts/dialog.gd"):
        print("=== ExitDialog ===")
        print("(skipped — dialog.gd not present in this project)")
        return
    var DialogScript = load("res://scripts/dialog.gd")
    var factory = func() -> Variant: return DialogScript.new()
    var events = [
        ["open",                []],
        ["confirm_quit",        []],
        ["confirm_save_quit",   []],
        ["cancel",              []],
    ]
    var report = StateExplorer.explore(factory, events)
    StateExplorer.print_report(report, "ExitDialog")
