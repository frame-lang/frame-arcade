extends SceneTree

# ============================================================
# test_cca_journey_completable.gd
# ============================================================
# Liveness / completability check — distinct from every other
# test in the suite, which measure REACHABILITY (can you get
# to state X?) and SAFETY (does any reachable state violate an
# invariant?). This one asks COMPLETABILITY: from state X, can
# the player still WIN?
#
# The property:
#
#   For every milestone the canonical journey passes through,
#   restoring that milestone's save-state snapshot and replaying
#   the REMAINING journey reaches $Won.
#
# This is the "save mid-game, reload, and still finish" property
# — load-bearing for the actual playable game (CCA supports
# SAVE/RESTORE). It also proves no canonical milestone is a
# softlock: a state from which victory has become unreachable
# (treasure lost past a one-way gate, lamp dead before the
# endgame, a required item consumed, etc.). If restoring at
# milestone N and replaying the tail can't reach $Won, either
# the save/restore boundary corrupts state or milestone N is a
# dead end.
#
# Scope: canonical milestones only. Extension-journey terminals
# (PlantUnlock:PlantHugeGrown, RustyDoorUnlock:AtCanon91)
# deliberately leave the player off the canonical path mid-
# detour; proving they're completable needs a "rejoin the main
# line" path that doesn't exist yet. Documented limitation, not
# a silent gap.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

var failures: int = 0

func _init():
    print("=== Journey completability (resume-and-win) ===")
    print("")

    # Capture every milestone's snapshot in one full walk.
    var milestones: Array = []          # ordered [{name, bytes}]
    if not _capture_all(milestones):
        print("FAIL — couldn't walk the canonical journey to completion")
        quit(1)
        return
    print("Captured %d milestone snapshots" % milestones.size())
    print("")

    # For each milestone index i: restore snapshot[i], replay
    # milestones i+1..end, assert the result is $Won.
    var resume_failures: Array = []
    for i in range(milestones.size()):
        var name: String = milestones[i]["name"]
        var won: bool = _resume_and_complete(milestones[i]["bytes"], i)
        if won:
            print("  OK   resume @ [%2d] %-18s → won" % [i, name])
        else:
            print("  FAIL resume @ [%2d] %-18s → did NOT reach won" % [i, name])
            resume_failures.append(name)
            failures += 1

    print("")
    if failures == 0:
        print("PASS — every canonical milestone resumes to victory (%d milestones)" % [
            milestones.size()])
        quit(0)
        return
    print("FAIL — %d milestone(s) can't complete the journey: %s" % [
        failures, str(resume_failures)])
    quit(failures)

# Walk the canonical journey start-to-end through a real driver,
# recording (name, save_state bytes) at every milestone. Mirrors
# the canonical-journey test's FSM-shortcut handling.
func _capture_all(out_milestones: Array) -> bool:
    var driver = _make_driver()
    var j = CanonicalJourney._create()
    while not j.is_done():
        var state: String = j.state_name()
        _apply_shortcuts(driver, state)
        for cmd in j.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        out_milestones.append({
            "name": state,
            "bytes": driver.fsm.save_state(),
        })
        j.advance()
    # The last milestone should be at/after victory. Confirm the
    # full forward walk actually won — if not, the journey itself
    # is broken and the resume matrix is meaningless.
    return driver.fsm.endgame_state() == "won"

# Restore to the snapshot captured at milestone index
# `resume_after`, then replay every milestone after it. Returns
# true iff the FSM ends in the won endgame state.
func _resume_and_complete(snapshot: PackedByteArray, resume_after: int) -> bool:
    var driver = _make_driver()
    driver.fsm.restore_state(snapshot)
    # Reset driver-side session state (prompts) the same way the
    # BFS harness does — modal-prompt state doesn't survive a
    # restore boundary; the driver re-derives it from world state.
    driver.prompts = Cca.PromptDispatcher.new()
    if driver.fsm.player.get_state() == "dead":
        driver.prompts.offer_revive()

    var j = CanonicalJourney._create()
    var idx: int = 0
    while not j.is_done():
        var state: String = j.state_name()
        if idx > resume_after:
            _apply_shortcuts(driver, state)
            for cmd in j.commands_from_previous():
                driver._process_input(String(cmd).to_lower())
        idx += 1
        j.advance()
    return driver.fsm.endgame_state() == "won"

# FSM-shortcut milestones — TreasuresFilled (13 deposits) and
# InRepository (35 ticks). Documented in canonical_journey.fgd;
# the player-command equivalent would be ~150 commands of
# treasure-deposit grind with no new coverage.
func _apply_shortcuts(driver, state: String) -> void:
    if state == "TreasuresFilled":
        for i in 13:
            driver.fsm.endgame.treasure_deposited()
    elif state == "InRepository":
        for i in 35:
            driver.fsm.tick()

func _make_driver():
    var d = Driver.new()
    d.fsm = Cca.new()
    d.fsm.setup_default_aspects()
    d.fsm.dwarves_auto_woken = true
    d.prompts = Cca.PromptDispatcher.new()
    d.output = RichTextLabel.new()
    d.output.bbcode_enabled = true
    d.input = LineEdit.new()
    d.rng = RandomNumberGenerator.new()
    d.rng.seed = 42
    d._build_verb_synonyms_5()
    d._print_welcome()
    d._print_room()
    return d
