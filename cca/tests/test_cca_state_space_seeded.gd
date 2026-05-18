extends SceneTree

# ============================================================
# test_cca_state_space_seeded.gd
# ============================================================
# RFC-0002 demonstrator: BFS coverage seeded from a canonical-
# journey milestone snapshot.
#
# Companion to test_cca_state_space.gd (canonical-start BFS).
# That test reaches 16 of 140 canon locations because canonical
# play from cold start can't navigate the grate + dark-cave +
# lamp-light prerequisite chain within its action-ordering
# budget. This test demonstrates that handing the BFS a deeper
# milestone snapshot dramatically expands coverage.
#
# Flow:
#   1. Build a fresh Driver. Walk the canonical_journey FSM up
#      to the chosen milestone (`LampLit` at canon room 9 —
#      past the grate, lamp lit, ready for cave exploration).
#   2. Snapshot the FSM state via save_state().
#   3. Store the snapshot in a MilestoneRegistry.
#   4. Configure StateSpace with seed_bytes pointing at that
#      snapshot.
#   5. Run BFS. Compare the location count to the cold-start
#      BFS's 16/140.
#
# The journey-walking phase replays the canonical pickup chain
# (take keys/lamp/food/bottle, light lamp, walk to grate,
# unlock, descend) using real Driver._process_input. Every state
# the seeded BFS later reaches is therefore canonically player-
# reachable — the milestone seed is just a precomputed shortcut
# past the action-ordering bottleneck.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

# Milestone to seed the BFS from. `LampLit` is at canon room 9
# (below grate) with the lamp lit — the gate the cold-start BFS
# can't navigate.
const SEED_MILESTONE: String = "LampLit"

func _init():
    print("=== CCA state-space search (RFC-0002 milestone-seeded) ===")
    print("")

    # ----- Phase 1: walk the journey to capture snapshots -----
    var registry = MilestoneRegistry.new()
    var captured_at: String = _walk_journey_and_capture(registry, SEED_MILESTONE)
    if captured_at == "":
        print("FAIL — couldn't reach milestone '%s' via canonical journey" % SEED_MILESTONE)
        quit(1)
        return
    print("Captured %d snapshots; seeding BFS from '%s'" % [
        registry.size(), captured_at])
    print("")

    # ----- Phase 2: BFS from the seeded snapshot -----
    var s = StateSpace.new()
    s.seed = 42
    s.max_states = 10000
    s.seed_bytes = registry.get_snapshot("canonical_journey", SEED_MILESTONE)
    s.seed_label = "canonical_journey:%s" % SEED_MILESTONE
    s.run()
    s.report()
    print("")

    if s.violations.is_empty():
        print("PASS — milestone-seeded BFS clean (%d states, %d locations)" % [
            s.states_visited, _location_count(s)])
        quit(0)
        return
    print("FAIL — %d invariant violation(s) in seeded BFS" % s.violations.size())
    quit(s.violations.size())

# Drives the canonical_journey FSM through real Driver commands,
# snapshotting at every milestone state. Returns the final
# milestone reached, or "" if the target milestone was never hit.
#
# Reuses the canonical-journey harness pattern. Stops walking
# once the chosen target milestone has been recorded — the rest
# of the canonical journey isn't needed for this seeded BFS.
func _walk_journey_and_capture(registry, target_milestone: String) -> String:
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    driver.fsm.wake_dwarves()    # match canonical-journey test setup
    driver.prompts = Cca.PromptDispatcher.new()
    driver.output = RichTextLabel.new()
    driver.output.bbcode_enabled = true
    driver.input = LineEdit.new()
    driver.rng = RandomNumberGenerator.new()
    driver.rng.seed = 42
    driver._build_verb_synonyms_5()

    # Prime room-1 state the way Driver._ready would.
    driver._print_welcome()
    driver._print_room()

    var journey = CanonicalJourney._create()
    var last_captured: String = ""
    while not journey.is_done():
        var state_name: String = journey.state_name()
        for cmd in journey.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        # Snapshot post-commands — this is the canonical state at
        # this milestone. Bytes are restorable into any fresh
        # Cca() instance.
        registry.record("canonical_journey", state_name,
            driver.fsm.save_state())
        last_captured = state_name
        if state_name == target_milestone:
            return state_name
        journey.advance()
    return last_captured

# Count distinct canon rooms reached in the BFS visited set.
# Mirror the per-location parsing in state_space.gd::report().
func _location_count(s) -> int:
    var rooms: Dictionary = {}
    for h in s.visited.keys():
        var room: int = int(h.substr(2).get_slice("|", 0))
        rooms[room] = true
    return rooms.size()
