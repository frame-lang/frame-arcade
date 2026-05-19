extends SceneTree

# ============================================================
# test_cca_state_space_seeded_endgame.gd
# ============================================================
# RFC-0002 milestone-seeded BFS for endgame mechanics.
#
# Three seed milestones reaching progressively into the late
# game:
#
#   BearReleased   — bear no longer following; player at canon
#                    130 unencumbered. Player-canonically
#                    reached.
#   GoldDeposited  — gold treasure deposited at well-house;
#                    score and treasures_deposited counter
#                    reflect one deposit. Player-canonically
#                    reached.
#   InRepository   — player teleported to canon 116
#                    (repository) after endgame closing.
#                    Uses canonical_journey's FSM-shortcut
#                    (treasure_deposited × 13 + tick × 35)
#                    rather than walking 15 canonical deposits.
#                    Tests endgame-state-machine mechanics
#                    (BLAST, closing-phase, repository teleport)
#                    without proving pure player-reachability.
#
# The middle two are still pure canonical play. InRepository
# specifically tests state-machine behaviour from a state that
# canonical play CAN reach (canonical_journey reaches it after
# 15 treasure deposits) but our test harness shortcuts the
# arrival to keep runtime bounded.
# ============================================================

const Cca = preload("res://scripts/cca.gd")
const Driver = preload("res://scripts/driver.gd")
const StateSpace = preload("res://scripts/state_space.gd")
const MilestoneRegistry = preload("res://scripts/milestone_registry.gd")
const CanonicalJourney = preload("res://scripts/canonical_journey.gd")

const SEED_MILESTONES: Array = ["BearReleased", "GoldDeposited", "InRepository"]
const PER_SEED_CAP: int = 1500

var total_violations: int = 0
var coverage_progression: Array = []

func _init():
    print("=== CCA state-space search (endgame progression) ===")
    print("")

    var registry = MilestoneRegistry.new()
    if not _walk_journey_to_deepest(registry, SEED_MILESTONES):
        print("FAIL — couldn't reach deepest milestone")
        quit(1)
        return
    print("Captured %d snapshots; running BFS from %d seed milestones" % [
        registry.size(), SEED_MILESTONES.size()])
    print("")

    for milestone in SEED_MILESTONES:
        if not registry.has("canonical_journey", milestone):
            print("--- SKIP: '%s' not in registry ---" % milestone)
            continue
        _run_seeded_bfs(registry, milestone)
        print("")

    print("=== Endgame progression ===")
    for entry in coverage_progression:
        print("  %-20s  %2d locations  %4d states" % [
            entry.milestone, entry.locations, entry.states])
    print("")

    if total_violations == 0:
        print("PASS — all endgame milestone-seeded BFS runs clean")
        quit(0)
        return
    print("FAIL — %d invariant violation(s) across endgame BFS runs" %
        total_violations)
    quit(total_violations)

# Walks canonical_journey, capturing snapshots. Mirrors
# test_cca_canonical_journey.gd's FSM-shortcut logic for two
# states (TreasuresFilled and InRepository) that the journey
# itself uses direct FSM manipulation for.
func _walk_journey_to_deepest(registry, targets: Array) -> bool:
    var driver = Driver.new()
    driver.fsm = Cca.new()
    driver.fsm.setup_default_aspects()
    driver.fsm.wake_dwarves()
    driver.prompts = Cca.PromptDispatcher.new()
    driver.output = RichTextLabel.new()
    driver.output.bbcode_enabled = true
    driver.input = LineEdit.new()
    driver.rng = RandomNumberGenerator.new()
    driver.rng.seed = 42
    driver._build_verb_synonyms_5()
    driver._print_welcome()
    driver._print_room()

    var journey = CanonicalJourney._create()
    var captured: Dictionary = {}
    var deepest_target: String = targets[targets.size() - 1]

    while not journey.is_done():
        var state_name: String = journey.state_name()
        # Canonical-journey FSM-shortcut handling — mirrors
        # test_cca_canonical_journey.gd lines 135-144.
        if state_name == "TreasuresFilled":
            for i in 13:
                driver.fsm.endgame.treasure_deposited()
        elif state_name == "InRepository":
            for i in 35:
                driver.fsm.tick()
        for cmd in journey.commands_from_previous():
            driver._process_input(String(cmd).to_lower())
        registry.record("canonical_journey", state_name, driver.fsm.save_state())
        captured[state_name] = true
        if state_name == deepest_target:
            return true
        journey.advance()
    for t in targets:
        if not captured.has(t):
            print("  missing milestone: %s" % t)
            return false
    return true

func _run_seeded_bfs(registry, milestone: String) -> void:
    print("--- BFS from '%s' ---" % milestone)
    var s = StateSpace.new()
    s.seed = 42
    s.max_states = PER_SEED_CAP
    s.seed_bytes = registry.get_snapshot("canonical_journey", milestone)
    s.seed_label = "canonical_journey:%s" % milestone
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
    coverage_progression.append({
        "milestone": milestone,
        "states":    s.states_visited,
        "locations": loc_count,
    })
    total_violations += s.violations.size()

func _location_count(s) -> int:
    var rooms: Dictionary = {}
    for h in s.visited.keys():
        var room: int = int(h.substr(2).get_slice("|", 0))
        rooms[room] = true
    return rooms.size()
