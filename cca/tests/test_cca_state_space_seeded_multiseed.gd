extends SceneTree

# ============================================================
# test_cca_state_space_seeded_multiseed.gd
# ============================================================
# RFC-0002 milestone-seeded BFS under multiple RNG seeds.
# Companion to test_cca_state_space_seeded_post_bridge.gd
# (single-seed BearFed test). This file re-walks the canonical
# journey to BearFed under FOUR different RNG seeds, then runs
# BFS from each resulting snapshot.
#
# Purpose: each RNG seed unfolds a different slice of CCA's
# probabilistic mechanics (Witt's End 95/5, dark-pit 35%,
# dwarf walks per-NPC RNG, pirate stalking, Y2 hollow-voice
# 25%). State hashes don't include RNG, so the same milestone
# state under different seeds may have different next-state
# distributions when BFS explores from it. Bugs that only
# surface under a specific RNG outcome show up in only that
# seed's run.
#
# Seeds chosen: 42, 99, 1234, 7777 — same set the probe uses
# for its multi-seed walks.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

const SEED_LIST: Array = [42, 99, 1234, 7777]
const TARGET_MILESTONE: String = "BearFed"
# Per-seed BFS cap. 1000 lets each seed converge naturally
# (single-seed BearFed reached ~619 states without binding).
# Total runtime ~2:30 for 4 seeds; the run_tests.sh timeout
# is raised to accommodate (the test is honest about its cost
# rather than truncated to fit an artificial budget).
const PER_SEED_CAP: int = 1000

var total_violations: int = 0

func _init():
    print("=== CCA state-space search (multi-seed at BearFed) ===")
    print("")

    for rng_seed in SEED_LIST:
        _run_one_seed(rng_seed)
        print("")

    if total_violations == 0:
        print("PASS — BearFed-seeded BFS clean under all %d RNG seeds" %
            SEED_LIST.size())
        quit(0)
        return
    print("FAIL — %d invariant violation(s) across multi-seed BFS runs" %
        total_violations)
    quit(total_violations)

func _run_one_seed(rng_seed: int) -> void:
    print("--- RNG seed %d ---" % rng_seed)
    var registry = MilestoneRegistry.new()
    if not _walk_journey_to_milestone(registry, TARGET_MILESTONE, rng_seed):
        print("  SKIP: couldn't reach milestone under seed %d" % rng_seed)
        return
    var s = StateSpace.new()
    s.seed = rng_seed
    s.max_states = PER_SEED_CAP
    s.seed_bytes = registry.get_snapshot("canonical_journey", TARGET_MILESTONE)
    s.seed_label = "canonical_journey:%s rng=%d" % [TARGET_MILESTONE, rng_seed]
    s.run()
    var loc_count: int = _location_count(s)
    print("  states: %d   locations: %d   violations: %d" % [
        s.states_visited, loc_count, s.violations.size()])
    if s.violations.size() > 0:
        var by_reason: Dictionary = {}
        for v in s.violations:
            var reason: String = v["reason"]
            var prefix: String = reason.split(":")[0]
            by_reason[prefix] = by_reason.get(prefix, 0) + 1
        for prefix in by_reason.keys():
            print("    %4d × %s" % [by_reason[prefix], prefix])
        print("    sample: %s" % s.violations[0]["reason"])
    total_violations += s.violations.size()

func _walk_journey_to_milestone(registry, target: String, rng_seed: int) -> bool:
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    driver.fsm.dwarves_auto_woken = true    # short-circuit auto-wake; dwarves stay dormant
    driver.prompts = Cca.PromptDispatcher.new()
    driver.output = RichTextLabel.new()
    driver.output.bbcode_enabled = true
    driver.input = LineEdit.new()
    driver.rng = RandomNumberGenerator.new()
    driver.rng.seed = rng_seed
    driver._build_verb_synonyms_5()
    driver._print_welcome()
    driver._print_room()

    var journey = CanonicalJourney._create()
    while not journey.is_done():
        var state_name: String = journey.state_name()
        for cmd in journey.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        if state_name == target:
            registry.record("canonical_journey", state_name, driver.fsm.save_state())
            return true
        journey.advance()
    return false

func _location_count(s) -> int:
    var rooms: Dictionary = {}
    for h in s.visited.keys():
        var room: int = int(h.substr(2).get_slice("|", 0))
        rooms[room] = true
    return rooms.size()
